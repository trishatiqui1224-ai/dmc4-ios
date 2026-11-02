// Devil May Cry 4 iOS Port - Memory Capability Probe Implementation

#include <sys/sysctl.h>
#include "probe_memory.h"

namespace probe {

uint64_t GetDeviceRAM() {
    int mib[2] = {CTL_HW, HW_MEMSIZE};
    uint64_t mem = 0;
    size_t len = sizeof(mem);
    sysctl(mib, 2, &mem, &len, nullptr, 0);
    return mem;
}

} // namespace probe
