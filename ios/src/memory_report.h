// Devil May Cry 4 iOS Port - Memory Diagnostics
#pragma once

#include <cstddef>
#include <cstdint>

namespace memory_report {

uint64_t GetPhysicalMemoryBytes();
uint64_t GetResidentMemoryBytes();
uint64_t GetMemoryFootprintBytes();
void LogMemoryReport();

} // namespace memory_report
