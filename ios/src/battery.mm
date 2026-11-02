// Devil May Cry 4 iOS Port - Battery State & Thermal Monitoring

#import <UIKit/UIKit.h>

#include "battery.h"

namespace battery {

float GetLevel() {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    return [UIDevice currentDevice].batteryLevel;
}

bool IsCharging() {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    UIDeviceBatteryState state = [UIDevice currentDevice].batteryState;
    return (state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull);
}

bool IsLowPowerModeEnabled() {
    return [NSProcessInfo processInfo].isLowPowerModeEnabled;
}

NSProcessInfoThermalState GetThermalState() {
    return [NSProcessInfo processInfo].thermalState;
}

} // namespace battery
