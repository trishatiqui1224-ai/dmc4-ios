// Devil May Cry 4 iOS Port - Application Lifecycle Management
#pragma once

#import <UIKit/UIKit.h>

namespace lifecycle {

void RegisterLifecycleObservers();
bool IsAppInBackground();

} // namespace lifecycle
