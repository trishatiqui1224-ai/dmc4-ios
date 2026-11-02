// Devil May Cry 4 iOS Port - Application Lifecycle Management

#import <UIKit/UIKit.h>

#include <rex/logging.h>

#include "lifecycle.h"

namespace lifecycle {

static bool g_in_background = false;

void RegisterLifecycleObservers() {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification* _Nonnull note) {
        g_in_background = true;
        REXLOG_INFO("[DMC4 Lifecycle] App entered background. Suspending non-essential tasks.");
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification* _Nonnull note) {
        g_in_background = false;
        REXLOG_INFO("[DMC4 Lifecycle] App entered foreground. Resuming tasks.");
    }];
}

bool IsAppInBackground() {
    return g_in_background;
}

} // namespace lifecycle
