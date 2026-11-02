// Devil May Cry 4 iOS Port - High Precision Frame Clock & Pacing

#include <chrono>
#include <thread>
#include <mach/mach_time.h>

namespace dmc4::clock {

static uint64_t g_last_frame_mach = 0;

void PaceFrame(int target_fps) {
    if (target_fps <= 0) target_fps = 60;
    mach_timebase_info_data_t tb{};
    mach_timebase_info(&tb);

    uint64_t target_interval_ns = 1000000000ULL / target_fps;
    uint64_t now = mach_absolute_time();

    if (g_last_frame_mach != 0) {
        uint64_t elapsed_ns = (now - g_last_frame_mach) * tb.numer / tb.denom;
        if (elapsed_ns < target_interval_ns) {
            uint64_t sleep_ns = target_interval_ns - elapsed_ns;
            std::this_thread::sleep_for(std::chrono::nanoseconds(sleep_ns));
        }
    }
    g_last_frame_mach = mach_absolute_time();
}

} // namespace dmc4::clock
