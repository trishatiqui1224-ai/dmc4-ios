// Devil May Cry 4 iOS Port - Boot Tracing

#include <chrono>
#include <fstream>
#include <iostream>
#include <mutex>
#include <vector>

#include <rex/logging.h>

#include "boot_trace.h"

namespace boot_trace {

namespace {
std::mutex g_trace_mutex;
std::vector<std::string> g_entries;
} // namespace

void Init() {
    std::lock_guard<std::mutex> lock(g_trace_mutex);
    g_entries.clear();
    g_entries.push_back("[DMC4 Boot] Initialized tracing system.");
}

void Log(const std::string& message) {
    std::lock_guard<std::mutex> lock(g_trace_mutex);
    g_entries.push_back(message);
    REXLOG_INFO("[BOOT] {}", message);
}

void Flush() {
    std::lock_guard<std::mutex> lock(g_trace_mutex);
    // Flush to disk if needed
}

} // namespace boot_trace
