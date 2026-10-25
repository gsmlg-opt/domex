/* macOS unprivileged system probe: one newline-delimited JSON object per second.
 * Adapted from hologram_demo's system monitor. Built via DomexSensor.Probe
 * and the OS/architecture entry points in darwin/{arm64,x86_64}.c.
 * Mach, sysctl and IOKit sampling is shared by both macOS architectures.
 * Cumulative counters are deliberately not converted to rates here.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <errno.h>
#include <inttypes.h>
#include <libproc.h>
#include <limits.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/processor_set.h>
#include <math.h>
#include <net/if.h>
#include <net/if_media.h>
#include <net/if_mib.h>
#include <net/route.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/proc_info.h>
#include <sys/sockio.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <time.h>
#include <unistd.h>

static mach_port_t host_port;
static char model[256];
static char cpu_brand[256];

#ifndef PROBE_CORE_TYPES
#define PROBE_CORE_TYPES(count, types) ((void)0)
#endif

static void json_string(const char *text) {
    const unsigned char *p = (const unsigned char *)text;
    putchar('"');
    for (; *p; ++p) {
        switch (*p) {
        case '"': fputs("\\\"", stdout); break;
        case '\\': fputs("\\\\", stdout); break;
        case '\b': fputs("\\b", stdout); break;
        case '\f': fputs("\\f", stdout); break;
        case '\n': fputs("\\n", stdout); break;
        case '\r': fputs("\\r", stdout); break;
        case '\t': fputs("\\t", stdout); break;
        default:
            if (*p < 0x20) printf("\\u%04x", (unsigned)*p);
            else putchar(*p);
        }
    }
    putchar('"');
}

static void nullable_u64(bool available, uint64_t value) {
    if (available) printf("%" PRIu64, value);
    else fputs("null", stdout);
}

static uint64_t clock_ms(clockid_t clock_id) {
    struct timespec ts;
    if (clock_gettime(clock_id, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

static void sysctl_string(const char *key, char *buf, size_t capacity,
                          const char *fallback) {
    size_t length = capacity - 1;
    if (sysctlbyname(key, buf, &length, NULL, 0) != 0 || length == 0)
        snprintf(buf, capacity, "%s", fallback);
    buf[capacity - 1] = '\0';
}

static bool cf_text(CFTypeRef value, char *buf, size_t capacity) {
    if (!value || capacity > LONG_MAX) return false;
    if (CFGetTypeID(value) == CFStringGetTypeID())
        return CFStringGetCString((CFStringRef)value, buf, (CFIndex)capacity,
                                  kCFStringEncodingUTF8);
    if (CFGetTypeID(value) == CFDataGetTypeID()) {
        CFDataRef data = (CFDataRef)value;
        const UInt8 *bytes = CFDataGetBytePtr(data);
        CFIndex length = CFDataGetLength(data);
        while (length > 0 && bytes[length - 1] == 0) --length;
        CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault, bytes,
                                     length, kCFStringEncodingUTF8, false);
        if (!string) return false;
        bool result = CFStringGetCString(string, buf, (CFIndex)capacity,
                                        kCFStringEncodingUTF8);
        CFRelease(string);
        return result;
    }
    return false;
}

static bool cf_u64(CFDictionaryRef dict, CFStringRef key, uint64_t *out) {
    if (!dict) return false;
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    int64_t number;
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID() ||
        !CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &number) ||
        number < 0) return false;
    *out = (uint64_t)number;
    return true;
}

static void print_cores(void) {
    natural_t count = 0;
    processor_info_array_t info = NULL;
    mach_msg_type_number_t info_count = 0;
    kern_return_t result = host_processor_info(host_port, PROCESSOR_CPU_LOAD_INFO,
                                              &count, &info, &info_count);
    putchar('[');
    if (result == KERN_SUCCESS && info_count >= count * CPU_STATE_MAX) {
        char *types = calloc(count, sizeof(*types));
        if (types) PROBE_CORE_TYPES(count, types);
        for (natural_t i = 0; i < count; ++i) {
            processor_cpu_load_info_t cpu = (processor_cpu_load_info_t)info + i;
            if (i) putchar(',');
            printf("{\"id\":%u,\"type\":", i + 1);
            if (types && types[i] == 'P') json_string("performance");
            else if (types && types[i] == 'E') json_string("efficiency");
            else fputs("null", stdout);
            printf(",\"user\":%" PRIu32 ",\"system\":%" PRIu32
                   ",\"nice\":%" PRIu32 ",\"idle\":%" PRIu32 "}",
                   (uint32_t)cpu->cpu_ticks[CPU_STATE_USER],
                   (uint32_t)cpu->cpu_ticks[CPU_STATE_SYSTEM],
                   (uint32_t)cpu->cpu_ticks[CPU_STATE_NICE],
                   (uint32_t)cpu->cpu_ticks[CPU_STATE_IDLE]);
        }
        free(types);
    } else {
        static bool warned;
        if (!warned) fprintf(stderr, "system_probe: CPU counters unavailable (%d)\n", result);
        warned = true;
    }
    if (info) vm_deallocate(mach_task_self(), (vm_address_t)info,
                            (vm_size_t)info_count * sizeof(integer_t));
    putchar(']');
}

static void print_process_counts(void) {
    int64_t processes = -1, threads = -1;
    int readable = 0;
    bool complete = false;
    processor_set_name_t set = MACH_PORT_NULL;
    if (processor_set_default(host_port, &set) == KERN_SUCCESS) {
        processor_set_load_info_data_t load;
        mach_msg_type_number_t count = PROCESSOR_SET_LOAD_INFO_COUNT;
        if (processor_set_statistics(set, PROCESSOR_SET_LOAD_INFO,
                                    (processor_set_info_t)&load, &count) == KERN_SUCCESS &&
            count >= PROCESSOR_SET_LOAD_INFO_COUNT &&
            load.task_count >= 0 && load.thread_count >= 0) {
            processes = load.task_count;
            threads = load.thread_count;
            complete = true;
        }
        mach_port_deallocate(mach_task_self(), set);
    }

    int required = proc_listallpids(NULL, 0);
    if (required > 0 && required < INT_MAX / (int)sizeof(pid_t) - 256) {
        int capacity = required + 256;
        pid_t *pids = calloc((size_t)capacity, sizeof(*pids));
        if (pids) {
            int found = proc_listallpids(pids, capacity * (int)sizeof(*pids));
            if (found > 0 && found < capacity) {
                if (processes < 0) processes = found;
                uint64_t partial_threads = 0;
                for (int i = 0; i < found; ++i) {
                    struct proc_taskinfo task;
                    if (proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &task,
                                     sizeof(task)) == sizeof(task)) {
                        ++readable;
                        partial_threads += task.pti_threadnum;
                    }
                }
                if (!complete && readable > 0 && partial_threads <= INT64_MAX)
                    threads = (int64_t)partial_threads;
            }
            free(pids);
        }
    }
    fputs(",\"processes\":", stdout);
    nullable_u64(processes >= 0, (uint64_t)processes);
    fputs(",\"threads\":", stdout);
    nullable_u64(threads >= 0, (uint64_t)threads);
    printf(",\"threads_complete\":%s,\"processes_readable\":%d",
           complete ? "true" : "false", readable);
}

static void print_memory(void) {
    vm_statistics64_data_t vm = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    bool available = host_statistics64(host_port, HOST_VM_INFO64,
                     (host_info64_t)&vm, &count) == KERN_SUCCESS;
    vm_size_t page_size = 0;
    available = available && host_page_size(host_port, &page_size) == KERN_SUCCESS;
    uint64_t physical = 0;
    size_t size = sizeof(physical);
    bool have_physical = sysctlbyname("hw.memsize", &physical, &size, NULL, 0) == 0;
    struct xsw_usage swap = {0};
    size = sizeof(swap);
    bool have_swap = sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0;
    int pressure = 0;
    size = sizeof(pressure);
    bool have_pressure = sysctlbyname("kern.memorystatus_vm_pressure_level",
                          &pressure, &size, NULL, 0) == 0 &&
                         (pressure == 1 || pressure == 2 || pressure == 4);
    fputs(",\"memory\":{\"physical\":", stdout);
    nullable_u64(have_physical, physical);
#define VM_FIELD(name, field) do { \
    fputs(",\"" name "\":", stdout); \
    nullable_u64(available, (uint64_t)vm.field * (uint64_t)page_size); \
} while (0)
    VM_FIELD("free", free_count);
    VM_FIELD("active", active_count);
    VM_FIELD("inactive", inactive_count);
    VM_FIELD("speculative", speculative_count);
    VM_FIELD("wired", wire_count);
    VM_FIELD("compressed", compressor_page_count);
    VM_FIELD("purgeable", purgeable_count);
    VM_FIELD("file_backed", external_page_count);
    VM_FIELD("anonymous", internal_page_count);
#undef VM_FIELD
    fputs(",\"swap_used\":", stdout);
    nullable_u64(have_swap, swap.xsu_used);
    fputs(",\"swap_total\":", stdout);
    nullable_u64(have_swap, swap.xsu_total);
    fputs(",\"pressure\":", stdout);
    nullable_u64(have_pressure, (uint64_t)pressure);
    putchar('}');
}

/* Inspect only narrow ancestor properties, never recursive registry dumps.
 * Disk image block drivers share the storage class with physical devices.
 */
static bool virtual_storage(io_registry_entry_t entry) {
    io_registry_entry_t current = entry;
    IOObjectRetain(current);
    bool virtual = false;
    for (unsigned depth = 0; depth < 16 && current; ++depth) {
        CFTypeRef value = IORegistryEntryCreateCFProperty(current,
                         CFSTR("Protocol Characteristics"), kCFAllocatorDefault, 0);
        if (value && CFGetTypeID(value) == CFDictionaryGetTypeID()) {
            char interconnect[256];
            if (cf_text(CFDictionaryGetValue((CFDictionaryRef)value,
                        CFSTR("Physical Interconnect")), interconnect,
                        sizeof(interconnect)) &&
                (strstr(interconnect, "Virtual") || strstr(interconnect, "Disk Image")))
                virtual = true;
        }
        if (value) CFRelease(value);
        if (IOObjectConformsTo(current, "IOHDIXHDDrive") ||
            IOObjectConformsTo(current, "IOHDIXHDDriveInKernel")) virtual = true;
        io_registry_entry_t parent = MACH_PORT_NULL;
        kern_return_t result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
        IOObjectRelease(current);
        current = result == KERN_SUCCESS ? parent : MACH_PORT_NULL;
        if (virtual) break;
    }
    if (current) IOObjectRelease(current);
    return virtual;
}

static bool whole_disk_name(io_registry_entry_t driver, char *name, size_t capacity) {
    io_iterator_t children = MACH_PORT_NULL;
    if (IORegistryEntryGetChildIterator(driver, kIOServicePlane, &children) != KERN_SUCCESS)
        return false;
    bool found = false;
    io_registry_entry_t child;
    while ((child = IOIteratorNext(children))) {
        if (IOObjectConformsTo(child, "IOMedia")) {
            CFTypeRef whole = IORegistryEntryCreateCFProperty(child, CFSTR("Whole"),
                                                              kCFAllocatorDefault, 0);
            if (whole && CFGetTypeID(whole) == CFBooleanGetTypeID() &&
                CFBooleanGetValue((CFBooleanRef)whole)) {
                CFTypeRef bsd = IORegistryEntryCreateCFProperty(child, CFSTR("BSD Name"),
                                                               kCFAllocatorDefault, 0);
                found = cf_text(bsd, name, capacity);
                if (bsd) CFRelease(bsd);
            }
            if (whole) CFRelease(whole);
        }
        IOObjectRelease(child);
        if (found) break;
    }
    IOObjectRelease(children);
    return found;
}

static void print_disk(void) {
    const CFStringRef keys[4] = {CFSTR("Bytes (Read)"), CFSTR("Bytes (Write)"),
                                 CFSTR("Operations (Read)"), CFSTR("Operations (Write)")};
    const char *names[4] = {"read_bytes", "write_bytes", "read_ops", "write_ops"};
    uint64_t totals[4] = {0};
    bool complete[4] = {true, true, true, true};
    bool any_metric = false;
    unsigned devices = 0;
    io_iterator_t iterator = MACH_PORT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault,
                           IOServiceMatching("IOBlockStorageDriver"), &iterator);
    fputs(",\"disk\":{\"devices\":[", stdout);
    if (result == KERN_SUCCESS) {
        io_service_t driver;
        while ((driver = IOIteratorNext(iterator))) {
            char name[256];
            if (!virtual_storage(driver) && whole_disk_name(driver, name, sizeof(name))) {
                CFTypeRef statistics = IORegistryEntryCreateCFProperty(driver,
                                        CFSTR("Statistics"), kCFAllocatorDefault, 0);
                CFDictionaryRef dict = statistics && CFGetTypeID(statistics) == CFDictionaryGetTypeID()
                                     ? (CFDictionaryRef)statistics : NULL;
                if (devices++) putchar(',');
                json_string(name);
                for (unsigned i = 0; i < 4; ++i) {
                    uint64_t value;
                    if (cf_u64(dict, keys[i], &value) && UINT64_MAX - totals[i] >= value) {
                        totals[i] += value;
                        any_metric = true;
                    } else complete[i] = false;
                }
                if (statistics) CFRelease(statistics);
            }
            IOObjectRelease(driver);
        }
        IOObjectRelease(iterator);
    }
    putchar(']');
    for (unsigned i = 0; i < 4; ++i) {
        printf(",\"%s\":", names[i]);
        nullable_u64(devices > 0 && complete[i], totals[i]);
    }
    printf(",\"available\":%s}", devices > 0 && any_metric ? "true" : "false");
}

static bool interface_active(int socket_fd, const char *name) {
    if (socket_fd < 0) return true;
    struct ifmediareq media = {0};
    snprintf(media.ifm_name, sizeof(media.ifm_name), "%s", name);
    if (ioctl(socket_fd, SIOCGIFMEDIA, &media) == 0 && (media.ifm_status & IFM_AVALID))
        return (media.ifm_status & IFM_ACTIVE) != 0;
    return true; /* Some legitimate network drivers do not implement media ioctls. */
}

static bool interface_counters(unsigned index, struct if_data64 *out) {
    int mib[] = {CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA,
                 (int)index, IFDATA_GENERAL};
    struct ifmibdata data = {0};
    size_t length = sizeof(data);
    if (sysctl(mib, 6, &data, &length, NULL, 0) != 0 || length < sizeof(data))
        return false;
    /* macOS 15 on this Intel Mac truncates the byte fields returned through
     * NET_RT_IFLIST2 despite its if_data64 ABI. The native interface MIB returns
     * the full 64-bit values (validated against netstat), so never use the
     * route snapshot's byte totals as a fallback. Route data enumerates links. */
    *out = data.ifmd_data;
    return true;
}

static void print_network(void) {
    int mib[] = {CTL_NET, PF_ROUTE, 0, AF_UNSPEC, NET_RT_IFLIST2, 0};
    size_t length = 0;
    char *buffer = NULL;
    bool available = false;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) == 0 && length > 0) {
        /* Interfaces may change between sizing and fetching. Retry ENOMEM. */
        for (unsigned attempt = 0; attempt < 3; ++attempt) {
            free(buffer);
            buffer = malloc(length);
            if (!buffer) break;
            size_t capacity = length;
            if (sysctl(mib, 6, buffer, &capacity, NULL, 0) == 0) {
                length = capacity;
                available = true;
                break;
            }
            if (errno != ENOMEM || sysctl(mib, 6, NULL, &length, NULL, 0) != 0) break;
        }
    }
    fputs(",\"network\":{\"interfaces\":[", stdout);
    int socket_fd = socket(AF_INET, SOCK_DGRAM, 0);
    bool complete = available;
    bool first = true;
    if (available) {
        /* Address records can be shorter than if_msghdr; inspect only the
         * common four-byte routing header before selecting RTM_IFINFO2. */
        struct route_header { uint16_t length; uint8_t version; uint8_t type; };
        for (size_t offset = 0; offset + sizeof(struct route_header) <= length;) {
            struct route_header *header = (struct route_header *)(buffer + offset);
            if (header->length < sizeof(*header) || header->length > length - offset)
                break;
            if (header->type == RTM_IFINFO2 && header->version == RTM_VERSION &&
                header->length >= sizeof(struct if_msghdr2)) {
                struct if_msghdr2 *info = (struct if_msghdr2 *)header;
                char name[IF_NAMESIZE];
                if (if_indextoname(info->ifm_index, name) && name[0] == 'e' && name[1] == 'n' &&
                    name[2] >= '0' && name[2] <= '9' &&
                    (info->ifm_flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING) &&
                    !(info->ifm_flags & (IFF_LOOPBACK | IFF_POINTOPOINT)) &&
                    interface_active(socket_fd, name)) {
                    struct if_data64 counters;
                    if (!interface_counters(info->ifm_index, &counters)) {
                        complete = false;
                        offset += header->length;
                        continue;
                    }
                    if (!first) putchar(',');
                    first = false;
                    fputs("{\"name\":", stdout);
                    json_string(name);
                    printf(",\"rx_bytes\":%" PRIu64 ",\"tx_bytes\":%" PRIu64
                           ",\"rx_packets\":%" PRIu64 ",\"tx_packets\":%" PRIu64 "}",
                           (uint64_t)counters.ifi_ibytes, (uint64_t)counters.ifi_obytes,
                           (uint64_t)counters.ifi_ipackets, (uint64_t)counters.ifi_opackets);
                }
            }
            offset += header->length;
        }
    }
    free(buffer);
    if (socket_fd >= 0) close(socket_fd);
    printf("],\"available\":%s}", complete ? "true" : "false");
}

static void gpu_name(io_registry_entry_t accelerator, char *name, size_t capacity) {
    io_registry_entry_t current = accelerator;
    IOObjectRetain(current);
    bool found = false;
    for (unsigned depth = 0; depth < 16 && current; ++depth) {
        if (IOObjectConformsTo(current, "IOPCIDevice")) {
            CFTypeRef value = IORegistryEntryCreateCFProperty(current, CFSTR("model"),
                                                              kCFAllocatorDefault, 0);
            found = cf_text(value, name, capacity);
            if (value) CFRelease(value);
        }
        io_registry_entry_t parent = MACH_PORT_NULL;
        kern_return_t result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
        IOObjectRelease(current);
        current = result == KERN_SUCCESS ? parent : MACH_PORT_NULL;
        if (found) break;
    }
    if (current) IOObjectRelease(current);
    if (!found) {
        io_name_t registry_name;
        if (IORegistryEntryGetName(accelerator, registry_name) == KERN_SUCCESS)
            snprintf(name, capacity, "%s", registry_name);
        else snprintf(name, capacity, "Unknown GPU");
    }
}

static bool gpu_utilization(CFDictionaryRef statistics, double *out) {
    const CFStringRef keys[] = {CFSTR("Device Utilization %"),
                               CFSTR("Device Utilization %%"),
                               CFSTR("Device Utilization % at cur p-state")};
    if (!statistics) return false;
    for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
        CFTypeRef value = CFDictionaryGetValue(statistics, keys[i]);
        double utilization;
        if (value && CFGetTypeID(value) == CFNumberGetTypeID() &&
            CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &utilization) &&
            isfinite(utilization) && utilization >= 0 && utilization <= 100) {
            *out = utilization;
            return true;
        }
    }
    return false;
}

static void print_gpu(void) {
    io_iterator_t iterator = MACH_PORT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault,
                           IOServiceMatching("IOAccelerator"), &iterator);
    fputs(",\"gpu\":[", stdout);
    bool first = true;
    if (result == KERN_SUCCESS) {
        io_service_t service;
        while ((service = IOIteratorNext(iterator))) {
            char name[512];
            gpu_name(service, name, sizeof(name));
            CFTypeRef value = IORegistryEntryCreateCFProperty(service,
                             CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
            CFDictionaryRef statistics = value && CFGetTypeID(value) == CFDictionaryGetTypeID()
                                       ? (CFDictionaryRef)value : NULL;
            double utilization = 0;
            bool available = gpu_utilization(statistics, &utilization);
            if (!first) putchar(',');
            first = false;
            fputs("{\"name\":", stdout);
            json_string(name);
            fputs(",\"utilization\":", stdout);
            if (available) printf("%.6g", utilization);
            else fputs("null", stdout);
            putchar('}');
            if (value) CFRelease(value);
            IOObjectRelease(service);
        }
        IOObjectRelease(iterator);
    }
    putchar(']');
}

static int sample(void) {
    printf("{\"timestamp_ms\":%" PRIu64 ",\"monotonic_ms\":%" PRIu64 ",\"model\":",
           clock_ms(CLOCK_REALTIME), clock_ms(CLOCK_MONOTONIC));
    json_string(model);
    fputs(",\"cpu_brand\":", stdout);
    json_string(cpu_brand);
    fputs(",\"cores\":", stdout);
    print_cores();
    print_process_counts();
    print_memory();
    print_disk();
    print_network();
    print_gpu();
    fputs("}\n", stdout);
    return fflush(stdout) == 0 && !ferror(stdout) ? 0 : 1;
}

int main(int argc, char **argv) {
    bool once = argc == 2 && strcmp(argv[1], "--once") == 0;
    if (argc > 2 || (argc == 2 && !once)) {
        fprintf(stderr, "usage: %s [--once]\n", argv[0]);
        return 2;
    }
    /* Port consumers close the pipe on shutdown; do not leave an orphan sampler. */
    signal(SIGPIPE, SIG_DFL);
    setvbuf(stdout, NULL, _IOLBF, 0);
    host_port = mach_host_self();
    sysctl_string("hw.model", model, sizeof(model), "Unknown Mac");
    sysctl_string("machdep.cpu.brand_string", cpu_brand, sizeof(cpu_brand), "Unknown CPU");
    struct timespec next;
    if (clock_gettime(CLOCK_MONOTONIC, &next) != 0) return 1;
    do {
        if (sample() != 0) return 1;
        if (once) break;
        ++next.tv_sec;
        struct timespec now;
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 1;
        if (now.tv_sec > next.tv_sec ||
            (now.tv_sec == next.tv_sec && now.tv_nsec >= next.tv_nsec)) {
            next = now;
            ++next.tv_sec;
        }
        struct timespec remaining = {next.tv_sec - now.tv_sec, next.tv_nsec - now.tv_nsec};
        if (remaining.tv_nsec < 0) { --remaining.tv_sec; remaining.tv_nsec += 1000000000; }
        while (nanosleep(&remaining, &remaining) != 0 && errno == EINTR) {}
    } while (!once);
    mach_port_deallocate(mach_task_self(), host_port);
    return 0;
}
