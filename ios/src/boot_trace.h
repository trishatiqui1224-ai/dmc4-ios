// Devil May Cry 4 iOS Port - Boot Tracing
#pragma once

#include <string>

namespace boot_trace {

void Init();
void Log(const std::string& message);
void Flush();

} // namespace boot_trace
