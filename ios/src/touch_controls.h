// Devil May Cry 4 iOS Port - Stylish Combat Touch Controls
#pragma once

#import <UIKit/UIKit.h>

namespace dmc4::touch {

enum class LeftThumbMode {
    AnalogStick = 0,   // Floating or fixed 360-degree analog stick
    Directional8Way = 1 // 8-Way rocker D-Pad for Back-to-Forward inputs (Stinger/Streak/High Time)
};

enum class LockOnMode {
    Hold = 0,   // Standard controller behavior: hold RB to lock
    Toggle = 1  // Mobile optimized: tap RB once to lock, tap again to unlock
};

struct TouchSettings {
    float opacity = 0.85f;
    float buttonScale = 1.0f;
    LeftThumbMode leftThumb = LeftThumbMode::AnalogStick;
    LockOnMode lockOn = LockOnMode::Toggle;
    bool autoChargeShotLatch = false; // Auto-hold X for Charge Shot 3
    bool hapticsEnabled = true;
    bool hideWhenControllerConnected = true;
    bool danteStyleCrossVisible = true;
    bool cameraPanZoneEnabled = true; // Touch & drag right side of screen to pan camera
    bool combatGesturesEnabled = true; // Swipe up/down for Streak/High Time, swipe Bringer for Snatch
};

// Initializes the Touch Overlay on the primary window/view
void InstallTouchOverlay(UIView* parentView);

// Re-asserts always-on-top zPosition (9999) after swapchain / CAMetalLayer updates
void BringTouchOverlayToFront();

// Updates live settings
void UpdateSettings(const TouchSettings& settings);
TouchSettings GetCurrentSettings();

// Toggles overlay visibility
void SetOverlayVisible(bool visible);
bool IsOverlayVisible();

} // namespace dmc4::touch
