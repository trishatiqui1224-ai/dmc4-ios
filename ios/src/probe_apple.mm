// Devil May Cry 4 iOS Port - Apple Device Probe Implementation

#import <UIKit/UIKit.h>
#include <sys/utsname.h>

#include "probe_apple.h"

namespace probe {

NSString* GetDeviceModel() {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

NSString* GetSystemVersion() {
    return [[UIDevice currentDevice] systemVersion];
}

} // namespace probe
