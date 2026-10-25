/* Apple Silicon macOS entry point; shared Mach/IOKit sampling stays in one file. */
#if !defined(__APPLE__) || !defined(__arm64__)
#error "The darwin-arm64 probe must be compiled for Apple Silicon macOS"
#endif

static void apple_core_types(unsigned count, char *types);
#define PROBE_CORE_TYPES(count, types) apple_core_types(count, types)
#include "../system_probe.c"

/* Match device-tree logical IDs to Mach processor slots. Performance-level
 * counts alone do not identify the type of an individual CPU load counter. */
static void apple_core_types(unsigned count, char *types) {
    natural_t basic_count = 0;
    processor_info_array_t basic_info = NULL;
    mach_msg_type_number_t info_count = 0;
    kern_return_t result = host_processor_info(host_port, PROCESSOR_BASIC_INFO,
                                               &basic_count, &basic_info, &info_count);
    if (result == KERN_SUCCESS && basic_count == count &&
        info_count >= count * PROCESSOR_BASIC_INFO_COUNT) {
        io_registry_entry_t cpus = IORegistryEntryFromPath(kIOMainPortDefault,
                                                          "IODeviceTree:/cpus");
        io_iterator_t children = MACH_PORT_NULL;
        if (cpus && IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane,
                                                   &children) == KERN_SUCCESS) {
            io_registry_entry_t child;
            while ((child = IOIteratorNext(children))) {
                CFTypeRef logical = IORegistryEntryCreateCFProperty(child,
                                     CFSTR("logical-cpu-id"), kCFAllocatorDefault, 0);
                CFTypeRef cluster = IORegistryEntryCreateCFProperty(child,
                                     CFSTR("cluster-type"), kCFAllocatorDefault, 0);
                int64_t logical_id;
                char kind[8];
                if (logical && CFGetTypeID(logical) == CFNumberGetTypeID() &&
                    CFNumberGetValue((CFNumberRef)logical, kCFNumberSInt64Type, &logical_id) &&
                    logical_id >= 0 && cf_text(cluster, kind, sizeof(kind)) &&
                    (strcmp(kind, "P") == 0 || strcmp(kind, "E") == 0)) {
                    for (natural_t i = 0; i < count; ++i) {
                        processor_basic_info_t basic = (processor_basic_info_t)basic_info + i;
                        if (basic->slot_num == logical_id) types[i] = kind[0];
                    }
                }
                if (logical) CFRelease(logical);
                if (cluster) CFRelease(cluster);
                IOObjectRelease(child);
            }
            IOObjectRelease(children);
        }
        if (cpus) IOObjectRelease(cpus);
    }
    if (basic_info) vm_deallocate(mach_task_self(), (vm_address_t)basic_info,
                                 (vm_size_t)info_count * sizeof(integer_t));
}
