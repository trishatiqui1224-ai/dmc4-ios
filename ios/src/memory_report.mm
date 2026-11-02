// Devil May Cry 4 iOS Port - Memory Diagnostics

#import <Foundation/Foundation.h>

#include <mach/mach.h>
#include <sys/sysctl.h>

#include <rex/logging.h>

#include "memory_report.h"

namespace memory_report {

uint64_t GetPhysicalMemoryBytes() {
    return [NSProcessInfo processInfo].physicalMemory;
}

uint64_t GetResidentMemoryBytes() {
    mach_task_basic_info info{};
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
        return info.resident_size;
    }
    return 0;
}

uint64_t GetMemoryFootprintBytes() {
    task_vm_info_data_t vmInfo{};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count) == KERN_SUCCESS) {
        return vmInfo.phys_footprint;
    }
    return GetResidentMemoryBytes();
}

void LogMemoryReport() {
    uint64_t physical = GetPhysicalMemoryBytes();
    uint64_t footprint = GetMemoryFootprintBytes();
    REXLOG_INFO("[DMC4 Memory] Footprint: {:.1f} MB / Physical: {:.1f} MB ({:.1f}%)",
                footprint / (1024.0 * 1024.0),
                physical / (1024.0 * 1024.0),
                (double)footprint / physical * 100.0);
}

} // namespace memory_report
