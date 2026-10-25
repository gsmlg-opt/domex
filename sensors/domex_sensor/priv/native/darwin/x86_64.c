/* Intel macOS entry point. Keep this target independent of Apple Silicon builds. */
#if !defined(__APPLE__) || !defined(__x86_64__)
#error "The darwin-x86_64 probe must be compiled for Intel macOS"
#endif

#include "../system_probe.c"
