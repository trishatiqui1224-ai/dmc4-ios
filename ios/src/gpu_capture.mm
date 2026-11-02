// Devil May Cry 4 iOS Port - Metal GPU Frame Capture

#import <Metal/Metal.h>

#include <rex/logging.h>

#include "gpu_capture.h"

namespace gpu_capture {

void TriggerFrameCapture() {
    MTLCaptureManager* captureManager = [MTLCaptureManager sharedCaptureManager];
    if (@available(iOS 13.0, *)) {
        if (!captureManager.isCapturing) {
            MTLCaptureDescriptor* descriptor = [[MTLCaptureDescriptor alloc] init];
            descriptor.captureObject = MTLCreateSystemDefaultDevice();
            descriptor.destination = MTLCaptureDestinationDeveloperTools;
            NSError* error = nil;
            if ([captureManager startCaptureWithDescriptor:descriptor error:&error]) {
                REXLOG_INFO("[DMC4 GPU] Started Metal GPU capture session.");
            } else {
                REXLOG_WARN("[DMC4 GPU] Failed to start Metal GPU capture: {}",
                            error.localizedDescription.UTF8String);
            }
        } else {
            [captureManager stopCapture];
            REXLOG_INFO("[DMC4 GPU] Stopped Metal GPU capture session.");
        }
    }
}

} // namespace gpu_capture
