// Devil May Cry 4 iOS Port - Battery State & Thermal Monitoring
#pragma once

#import <UIKit/UIKit.h>

namespace battery {

float GetLevel();
bool IsCharging();
bool IsLowPowerModeEnabled();
NSProcessInfoThermalState GetThermalState();

} // namespace battery
