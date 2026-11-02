// Devil May Cry 4 iOS Port - ProMotion Display Rate & Refresh Pacing
#pragma once

#import <UIKit/UIKit.h>

namespace display_rate {

int GetMaxDisplayRefreshRate();
void SetPreferredFrameRate(int fps);
int GetCurrentPreferredFrameRate();

} // namespace display_rate
