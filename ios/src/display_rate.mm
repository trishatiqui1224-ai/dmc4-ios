// Devil May Cry 4 iOS Port - ProMotion Display Rate & Refresh Pacing

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include <rex/logging.h>

#include "display_rate.h"

namespace display_rate {

static int g_preferred_fps = 60;

int GetMaxDisplayRefreshRate() {
    UIScreen* mainScreen = [UIScreen mainScreen];
    if (@available(iOS 10.3, *)) {
        return static_cast<int>(mainScreen.maximumFramesPerSecond);
    }
    return 60;
}

void SetPreferredFrameRate(int fps) {
    g_preferred_fps = fps;
    REXLOG_INFO("[DMC4 Display] Requested preferred frame rate: {} FPS (Max: {} FPS)",
                fps, GetMaxDisplayRefreshRate());
}

int GetCurrentPreferredFrameRate() {
    return g_preferred_fps;
}

} // namespace display_rate
