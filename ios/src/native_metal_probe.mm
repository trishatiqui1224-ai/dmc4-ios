// Devil May Cry 4 iOS Port - Native Metal Device Probe

#import <Metal/Metal.h>
#include <rex/logging.h>

namespace dmc4::metal {

void ProbeCapabilities() {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (device) {
        REXLOG_INFO("[DMC4 Metal] Metal Device: {}", device.name.UTF8String);
        if (@available(iOS 16.0, *)) {
            REXLOG_INFO("[DMC4 Metal] Supports Metal 3: {}", [device supportsFamily:MTLGPUFamilyMetal3] ? "YES" : "NO");
            REXLOG_INFO("[DMC4 Metal] Supports Apple 8 (A16/M2+): {}", [device supportsFamily:MTLGPUFamilyApple8] ? "YES" : "NO");
        }
    }
}

} // namespace dmc4::metal
