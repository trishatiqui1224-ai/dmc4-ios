// Devil May Cry 4 (Title ID: 434307DF) - Studio-Grade Combat Touch HUD
// Custom DMC4 Procedural Vector Glyphs, Nero Exceed Thumb-Slide, and Smart Combat HUD

#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include <SDL3/SDL.h>
#include <SDL3/SDL_joystick.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <vector>

#include <rex/cvar.h>
#include <rex/logging.h>

#include "battery.h"
#include "display_rate.h"
#include "ingame_options.h"
#include "touch_controls.h"

// ---------------------------------------------------------------------------
//  Virtual Gamepad Button Bitmasks (Standard Xbox 360 mapping)
// ---------------------------------------------------------------------------

namespace {

constexpr int kA      = 1 << 0;  // Jump / Evade
constexpr int kB      = 1 << 1;  // Devil Bringer / Buster / Style Action
constexpr int kX      = 1 << 2;  // Gun Shoot (Blue Rose / E&I)
constexpr int kY      = 1 << 3;  // Melee (Red Queen / Rebellion)
constexpr int kBack   = 1 << 4;  // Taunt
constexpr int kGuide  = 1 << 5;  // Home
constexpr int kStart  = 1 << 6;  // Pause / Menu
constexpr int kL3     = 1 << 7;  // Left Thumb Click
constexpr int kR3     = 1 << 8;  // Reset Camera / Lock Target Reset
constexpr int kLB     = 1 << 9;  // Devil Trigger (DT)
constexpr int kRB     = 1 << 10; // Lock-On
constexpr int kUp     = 1 << 11; // Trickster
constexpr int kDown   = 1 << 12; // Royalguard
constexpr int kLeft   = 1 << 13; // Gunslinger
constexpr int kRight  = 1 << 14; // Swordmaster

constexpr int kAxes = 6; // LX (0), LY (1), RX (2), RY (3), LT (4), RT (5)

SDL_Joystick* g_virtual_pad = nullptr;
int g_active_buttons = 0;
Sint16 g_axes[kAxes] = {0};

void EnsureVirtualPadInitialized() {
    if (g_virtual_pad) return;

    SDL_VirtualJoystickDesc desc;
    SDL_INIT_INTERFACE(&desc);
    desc.type = SDL_JOYSTICK_TYPE_GAMEPAD;
    desc.naxes = kAxes;
    desc.nbuttons = 16;
    desc.name = "Devil May Cry 4 iOS Virtual Gamepad";

    SDL_JoystickID jid = SDL_AttachVirtualJoystick(&desc);
    if (jid != 0) {
        g_virtual_pad = SDL_OpenJoystick(jid);
        REXLOG_INFO("[DMC4 Touch] Attached and opened virtual gamepad with instance ID {}", jid);
    } else {
        REXLOG_WARN("[DMC4 Touch] SDL_AttachVirtualJoystick failed: {}", SDL_GetError());
    }
}

void SyncVirtualPadState() {
    EnsureVirtualPadInitialized();
    if (!g_virtual_pad) return;
    for (int i = 0; i < 15; ++i) {
        bool pressed = (g_active_buttons & (1 << i)) != 0;
        SDL_SetJoystickVirtualButton(g_virtual_pad, i, pressed);
    }
    for (int a = 0; a < kAxes; ++a) {
        SDL_SetJoystickVirtualAxis(g_virtual_pad, a, g_axes[a]);
    }
}

void SetButtonBit(int bit, bool pressed) {
    if (pressed) {
        g_active_buttons |= bit;
    } else {
        g_active_buttons &= ~bit;
    }
    SyncVirtualPadState();
}

void SetAxisValue(int axis_idx, Sint16 val) {
    if (axis_idx >= 0 && axis_idx < kAxes) {
        g_axes[axis_idx] = val;
        SyncVirtualPadState();
    }
}

} // namespace

// ---------------------------------------------------------------------------
//  DMC4 Procedural Vector Glyphs (CoreGraphics 120Hz Retina Sharp)
// ---------------------------------------------------------------------------

namespace dmc4::icons {

UIImage* RenderIcon(CGSize size, void (^drawingBlock)(CGContextRef ctx, CGRect rect)) {
    UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext* _Nonnull rendererContext) {
        CGContextRef ctx = rendererContext.CGContext;
        drawingBlock(ctx, CGRectMake(0, 0, size.width, size.height));
    }];
}

// 1. Melee: Authentic Red Queen / Rebellion Broadsword with combustion engine exhaust
UIImage* CreateMeleeSwordIcon(CGFloat size, UIColor* tint) {
    return RenderIcon(CGSizeMake(size, size), ^(CGContextRef ctx, CGRect rect) {
        CGFloat w = rect.size.width;
        CGFloat h = rect.size.height;
        CGFloat cx = w / 2.0f;
        CGFloat cy = h / 2.0f;

        [tint setStroke];
        [tint setFill];

        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, cx, cy);
        CGContextRotateCTM(ctx, -M_PI_4);

        // Heavy double-edged blade with serrated blood groove
        UIBezierPath* blade = [UIBezierPath bezierPath];
        [blade moveToPoint:CGPointMake(0, -h * 0.44f)]; // Pointed tip
        [blade addLineToPoint:CGPointMake(w * 0.085f, -h * 0.36f)];
        [blade addLineToPoint:CGPointMake(w * 0.075f, -h * 0.10f)]; // Upper edge
        [blade addLineToPoint:CGPointMake(w * 0.11f, -h * 0.05f)];  // Serrated hook
        [blade addLineToPoint:CGPointMake(w * 0.075f, 0.0f)];
        [blade addLineToPoint:CGPointMake(w * 0.075f, h * 0.16f)];  // Base of blade

        // Red Queen Engine Crossguard (motorcycle cylinder block)
        [blade addLineToPoint:CGPointMake(w * 0.22f, h * 0.18f)]; // Right exhaust manifold
        [blade addLineToPoint:CGPointMake(w * 0.18f, h * 0.23f)];
        [blade addLineToPoint:CGPointMake(w * 0.06f, h * 0.22f)];

        // Motorcycle Throttle Rev Grip & Pommel
        [blade addLineToPoint:CGPointMake(w * 0.045f, h * 0.38f)]; // Grip
        [blade addLineToPoint:CGPointMake(w * 0.08f, h * 0.40f)];  // Beveled pommel
        [blade addLineToPoint:CGPointMake(0, h * 0.45f)];          // Pommel tip
        [blade addLineToPoint:CGPointMake(-w * 0.08f, h * 0.40f)];
        [blade addLineToPoint:CGPointMake(-w * 0.045f, h * 0.38f)];

        // Left crossguard & engine manifold
        [blade addLineToPoint:CGPointMake(-w * 0.06f, h * 0.22f)];
        [blade addLineToPoint:CGPointMake(-w * 0.18f, h * 0.23f)];
        [blade addLineToPoint:CGPointMake(-w * 0.22f, h * 0.18f)];
        [blade addLineToPoint:CGPointMake(-w * 0.075f, h * 0.16f)];

        // Left blade edge
        [blade addLineToPoint:CGPointMake(-w * 0.075f, 0.0f)];
        [blade addLineToPoint:CGPointMake(-w * 0.11f, -h * 0.05f)];
        [blade addLineToPoint:CGPointMake(-w * 0.075f, -h * 0.10f)];
        [blade addLineToPoint:CGPointMake(-w * 0.085f, -h * 0.36f)];
        [blade closePath];

        blade.lineWidth = 1.6f;
        [blade stroke];
        CGContextSetAlpha(ctx, 0.40f);
        [blade fill];

        // Central blade fuller rib
        CGContextSetAlpha(ctx, 0.90f);
        UIBezierPath* fuller = [UIBezierPath bezierPath];
        [fuller moveToPoint:CGPointMake(0, -h * 0.35f)];
        [fuller addLineToPoint:CGPointMake(0, h * 0.12f)];
        fuller.lineWidth = 1.5f;
        [fuller stroke];

        CGContextRestoreGState(ctx);

        // Twin Motorcycle Exhaust Flame Trails
        UIBezierPath* flameArc1 = [UIBezierPath bezierPath];
        [flameArc1 addArcWithCenter:CGPointMake(cx, cy) radius:w * 0.40f startAngle:M_PI * 0.55f endAngle:M_PI * 0.95f clockwise:YES];
        flameArc1.lineWidth = 2.4f;
        [flameArc1 stroke];

        UIBezierPath* flameArc2 = [UIBezierPath bezierPath];
        [flameArc2 addArcWithCenter:CGPointMake(cx, cy) radius:w * 0.33f startAngle:M_PI * 0.60f endAngle:M_PI * 0.90f clockwise:YES];
        flameArc2.lineWidth = 1.6f;
        CGContextSetAlpha(ctx, 0.65f);
        [flameArc2 stroke];
    });
}

// 2. Devil Bringer: Nero's Spectral Glowing Demon Claw (5 Articulated Talons & Core)
UIImage* CreateDevilBringerClawIcon(CGFloat size, UIColor* tint) {
    return RenderIcon(CGSizeMake(size, size), ^(CGContextRef ctx, CGRect rect) {
        CGFloat w = rect.size.width;
        CGFloat h = rect.size.height;
        CGFloat cx = w / 2.0f;
        CGFloat cy = h / 2.0f;

        [tint setStroke];
        [tint setFill];

        // 5 Demonic Talons with glowing curved knuckles
        for (int i = 0; i < 5; ++i) {
            CGFloat angle = -0.55f + i * 0.275f;
            UIBezierPath* talon = [UIBezierPath bezierPath];
            CGFloat startX = cx - w * 0.22f + i * (w * 0.11f);
            CGFloat startY = cy + h * 0.16f;

            CGPoint tip = CGPointMake(startX + sin(angle) * w * 0.38f, startY - cos(angle) * h * 0.48f);
            CGPoint ctrl1 = CGPointMake(startX + sin(angle) * w * 0.12f, startY - h * 0.22f);
            CGPoint ctrl2 = CGPointMake(startX + sin(angle) * w * 0.32f + 2.0f, startY - h * 0.32f);

            [talon moveToPoint:CGPointMake(startX, startY)];
            [talon addCurveToPoint:tip controlPoint1:ctrl1 controlPoint2:ctrl2];
            [talon addQuadCurveToPoint:CGPointMake(startX + w * 0.05f, startY)
                          controlPoint:CGPointMake(startX + sin(angle) * w * 0.18f + 3.0f, startY - h * 0.16f)];
            [talon closePath];

            talon.lineWidth = 1.5f;
            CGContextSetAlpha(ctx, 1.0f);
            [talon stroke];
            CGContextSetAlpha(ctx, 0.45f);
            [talon fill];
        }

        // Spectral Palm Gem / Radiant Energy Core
        CGContextSetAlpha(ctx, 1.0f);
        UIBezierPath* palm = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - w * 0.13f, cy + h * 0.04f, w * 0.26f, h * 0.26f)];
        palm.lineWidth = 2.2f;
        [palm stroke];
        CGContextSetAlpha(ctx, 0.65f);
        [palm fill];

        // Demonic Forearm Vein Striations
        CGContextSetAlpha(ctx, 0.85f);
        UIBezierPath* vein = [UIBezierPath bezierPath];
        [vein moveToPoint:CGPointMake(cx - w * 0.10f, cy + h * 0.30f)];
        [vein addLineToPoint:CGPointMake(cx, cy + h * 0.17f)];
        [vein addLineToPoint:CGPointMake(cx + w * 0.10f, cy + h * 0.30f)];
        vein.lineWidth = 1.6f;
        [vein stroke];
    });
}

// 3. Shoot: Blue Rose Custom Twin-Barrel Revolver & Cylinder
UIImage* CreateShootGunIcon(CGFloat size, UIColor* tint) {
    return RenderIcon(CGSizeMake(size, size), ^(CGContextRef ctx, CGRect rect) {
        CGFloat w = rect.size.width;
        CGFloat h = rect.size.height;
        CGFloat cx = w / 2.0f;
        CGFloat cy = h / 2.0f;

        [tint setStroke];
        [tint setFill];

        // Top Magnum Barrel Muzzle
        UIBezierPath* barrelTop = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - w * 0.13f, cy - h * 0.26f, w * 0.26f, h * 0.20f)];
        barrelTop.lineWidth = 2.0f;
        [barrelTop stroke];
        UIBezierPath* rifling1 = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - w * 0.06f, cy - h * 0.20f, w * 0.12f, h * 0.08f)];
        [rifling1 fill];

        // Bottom Scatter-Shot Barrel Muzzle
        UIBezierPath* barrelBottom = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - w * 0.13f, cy + h * 0.05f, w * 0.26f, h * 0.20f)];
        barrelBottom.lineWidth = 2.0f;
        [barrelBottom stroke];
        UIBezierPath* rifling2 = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - w * 0.06f, cy + h * 0.11f, w * 0.12f, h * 0.08f)];
        [rifling2 fill];

        // Revolver Cylinder Flute Accents
        UIBezierPath* cylinderFrame = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - w * 0.22f, cy - h * 0.32f, w * 0.44f, h * 0.62f) cornerRadius:6.0f];
        cylinderFrame.lineWidth = 1.6f;
        CGContextSetAlpha(ctx, 0.45f);
        [cylinderFrame stroke];

        // Stylized Rose Emblem & Petal Crosshairs
        CGContextSetAlpha(ctx, 1.0f);
        UIBezierPath* cross = [UIBezierPath bezierPath];
        [cross moveToPoint:CGPointMake(cx - w * 0.36f, cy)];
        [cross addLineToPoint:CGPointMake(cx - w * 0.18f, cy)];
        [cross moveToPoint:CGPointMake(cx + w * 0.18f, cy)];
        [cross addLineToPoint:CGPointMake(cx + w * 0.36f, cy)];
        [cross moveToPoint:CGPointMake(cx, cy - h * 0.38f)];
        [cross addLineToPoint:CGPointMake(cx, cy - h * 0.29f)];
        [cross moveToPoint:CGPointMake(cx, cy + h * 0.27f)];
        [cross addLineToPoint:CGPointMake(cx, cy + h * 0.38f)];
        cross.lineWidth = 2.2f;
        [cross stroke];
    });
}

// 4. Jump: DMC4 Air Hike Runic Wings & Upward Launch Chevron
UIImage* CreateJumpWingsIcon(CGFloat size, UIColor* tint) {
    return RenderIcon(CGSizeMake(size, size), ^(CGContextRef ctx, CGRect rect) {
        CGFloat w = rect.size.width;
        CGFloat h = rect.size.height;
        CGFloat cx = w / 2.0f;
        CGFloat cy = h / 2.0f;

        [tint setStroke];
        [tint setFill];

        // Concentric Air Hike Magic Sigil Circle
        UIBezierPath* runeCircle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - w * 0.38f, cy - h * 0.38f, w * 0.76f, h * 0.76f)];
        runeCircle.lineWidth = 1.2f;
        CGFloat dash[] = { 4.0f, 3.0f };
        [runeCircle setLineDash:dash count:2 phase:0];
        CGContextSetAlpha(ctx, 0.55f);
        [runeCircle stroke];
        CGContextSetAlpha(ctx, 1.0f);

        // Left Demonic Bat Wing
        UIBezierPath* leftWing = [UIBezierPath bezierPath];
        [leftWing moveToPoint:CGPointMake(cx - 3.0f, cy + h * 0.20f)];
        [leftWing addCurveToPoint:CGPointMake(cx - w * 0.40f, cy - h * 0.24f)
                    controlPoint1:CGPointMake(cx - w * 0.16f, cy + h * 0.08f)
                    controlPoint2:CGPointMake(cx - w * 0.34f, cy - h * 0.02f)];
        [leftWing addQuadCurveToPoint:CGPointMake(cx - w * 0.24f, cy - h * 0.06f)
                         controlPoint:CGPointMake(cx - w * 0.30f, cy - h * 0.13f)];
        [leftWing addQuadCurveToPoint:CGPointMake(cx - w * 0.14f, cy + h * 0.12f)
                         controlPoint:CGPointMake(cx - w * 0.20f, cy + h * 0.05f)];
        [leftWing closePath];
        leftWing.lineWidth = 1.6f;
        [leftWing stroke];
        CGContextSetAlpha(ctx, 0.40f);
        [leftWing fill];

        // Right Angelic Feathered Wing
        CGContextSetAlpha(ctx, 1.0f);
        UIBezierPath* rightWing = [UIBezierPath bezierPath];
        [rightWing moveToPoint:CGPointMake(cx + 3.0f, cy + h * 0.20f)];
        [rightWing addCurveToPoint:CGPointMake(cx + w * 0.40f, cy - h * 0.24f)
                     controlPoint1:CGPointMake(cx + w * 0.16f, cy + h * 0.08f)
                     controlPoint2:CGPointMake(cx + w * 0.34f, cy - h * 0.02f)];
        [rightWing addQuadCurveToPoint:CGPointMake(cx + w * 0.24f, cy - h * 0.06f)
                          controlPoint:CGPointMake(cx + w * 0.30f, cy - h * 0.13f)];
        [rightWing addQuadCurveToPoint:CGPointMake(cx + w * 0.14f, cy + h * 0.12f)
                          controlPoint:CGPointMake(cx + w * 0.20f, cy + h * 0.05f)];
        [rightWing closePath];
        rightWing.lineWidth = 1.6f;
        [rightWing stroke];
        CGContextSetAlpha(ctx, 0.40f);
        [rightWing fill];

        // Central Air Hike Upward Propulsion Chevron
        CGContextSetAlpha(ctx, 1.0f);
        UIBezierPath* arrow = [UIBezierPath bezierPath];
        [arrow moveToPoint:CGPointMake(cx, cy - h * 0.36f)];
        [arrow addLineToPoint:CGPointMake(cx - w * 0.11f, cy - h * 0.18f)];
        [arrow addLineToPoint:CGPointMake(cx - w * 0.04f, cy - h * 0.18f)];
        [arrow addLineToPoint:CGPointMake(cx - w * 0.04f, cy + h * 0.02f)];
        [arrow addLineToPoint:CGPointMake(cx + w * 0.04f, cy + h * 0.02f)];
        [arrow addLineToPoint:CGPointMake(cx + w * 0.04f, cy - h * 0.18f)];
        [arrow addLineToPoint:CGPointMake(cx + w * 0.11f, cy - h * 0.18f)];
        [arrow closePath];
        [arrow fill];
    });
}

// 5. Exceed: Authentic 3-Flame Tachometer Dial with MAX-Act Redline (Nero Exceed)
UIImage* CreateExceedRevIcon(CGFloat size, UIColor* tint) {
    return RenderIcon(CGSizeMake(size, size), ^(CGContextRef ctx, CGRect rect) {
        CGFloat w = rect.size.width;
        CGFloat h = rect.size.height;
        CGFloat cx = w / 2.0f;
        CGFloat cy = h * 0.56f;
        CGFloat r = w * 0.38f;

        [tint setStroke];
        [tint setFill];

        // 240-Degree Speedometer / Tachometer Dial Arc
        UIBezierPath* dial = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx, cy)
                                                            radius:r
                                                        startAngle:M_PI * 0.78f
                                                          endAngle:M_PI * 2.22f
                                                         clockwise:YES];
        dial.lineWidth = 2.6f;
        [dial stroke];

        // Inner Sub-Gauge Arc
        UIBezierPath* innerDial = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx, cy)
                                                                 radius:r - 6.0f
                                                             startAngle:M_PI * 0.78f
                                                               endAngle:M_PI * 2.22f
                                                              clockwise:YES];
        innerDial.lineWidth = 1.0f;
        CGContextSetAlpha(ctx, 0.45f);
        [innerDial stroke];
        CGContextSetAlpha(ctx, 1.0f);

        // 3 Exceed Levels (EX1, EX2, EX3 / MAX-Act)
        for (int i = 0; i < 3; ++i) {
            CGFloat a = M_PI * 1.55f + i * 0.28f;
            CGFloat x1 = cx + cos(a) * (r - 4.0f);
            CGFloat y1 = cy + sin(a) * (r - 4.0f);
            CGFloat x2 = cx + cos(a) * (r + 7.0f);
            CGFloat y2 = cy + sin(a) * (r + 7.0f);

            UIBezierPath* notch = [UIBezierPath bezierPath];
            [notch moveToPoint:CGPointMake(x1, y1)];
            [notch addLineToPoint:CGPointMake(x2, y2)];
            notch.lineWidth = 3.2f;
            [notch stroke];
        }

        // Needle pointing directly to MAX-Act Redline
        UIBezierPath* needle = [UIBezierPath bezierPath];
        [needle moveToPoint:CGPointMake(cx, cy)];
        [needle addLineToPoint:CGPointMake(cx + cos(M_PI * 1.88f) * (r - 3.0f), cy + sin(M_PI * 1.88f) * (r - 3.0f))];
        needle.lineWidth = 2.8f;
        [needle stroke];

        // Center Gauge Hub & Engine Flame Burst
        UIBezierPath* hub = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 5.5f, cy - 5.5f, 11.0f, 11.0f)];
        [hub fill];

        // "EX" Label at base
        NSDictionary* attrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:9.0f weight:UIFontWeightHeavy],
            NSForegroundColorAttributeName: tint
        };
        [@"EX" drawAtPoint:CGPointMake(cx - 7.0f, cy + 8.0f) withAttributes:attrs];
    });
}

// 6. Lock-On: Demonic Eye Target Reticle with 4 Corner Brackets
UIImage* CreateLockOnReticleIcon(CGFloat size, UIColor* tint) {
    return RenderIcon(CGSizeMake(size, size), ^(CGContextRef ctx, CGRect rect) {
        CGFloat w = rect.size.width;
        CGFloat h = rect.size.height;
        CGFloat cx = w / 2.0f;
        CGFloat cy = h / 2.0f;

        [tint setStroke];
        [tint setFill];

        // Outer Targeting Ring with Segment Gaps
        UIBezierPath* ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - w * 0.35f, cy - h * 0.35f, w * 0.70f, h * 0.70f)];
        ring.lineWidth = 2.0f;
        CGFloat dash[] = { 10.0f, 5.0f };
        [ring setLineDash:dash count:2 phase:0];
        [ring stroke];

        // 4 Triangular Corner Brackets
        CGFloat span = w * 0.36f;
        CGFloat arm = w * 0.12f;

        // Top-Left
        UIBezierPath* b1 = [UIBezierPath bezierPath];
        [b1 moveToPoint:CGPointMake(cx - span, cy - span + arm)];
        [b1 addLineToPoint:CGPointMake(cx - span, cy - span)];
        [b1 addLineToPoint:CGPointMake(cx - span + arm, cy - span)];
        b1.lineWidth = 2.4f;
        [b1 stroke];

        // Top-Right
        UIBezierPath* b2 = [UIBezierPath bezierPath];
        [b2 moveToPoint:CGPointMake(cx + span - arm, cy - span)];
        [b2 addLineToPoint:CGPointMake(cx + span, cy - span)];
        [b2 addLineToPoint:CGPointMake(cx + span, cy - span + arm)];
        b2.lineWidth = 2.4f;
        [b2 stroke];

        // Bottom-Right
        UIBezierPath* b3 = [UIBezierPath bezierPath];
        [b3 moveToPoint:CGPointMake(cx + span, cy + span - arm)];
        [b3 addLineToPoint:CGPointMake(cx + span, cy + span)];
        [b3 addLineToPoint:CGPointMake(cx + span - arm, cy + span)];
        b3.lineWidth = 2.4f;
        [b3 stroke];

        // Bottom-Left
        UIBezierPath* b4 = [UIBezierPath bezierPath];
        [b4 moveToPoint:CGPointMake(cx - span + arm, cy + span)];
        [b4 addLineToPoint:CGPointMake(cx - span, cy + span)];
        [b4 addLineToPoint:CGPointMake(cx - span, cy + span - arm)];
        b4.lineWidth = 2.4f;
        [b4 stroke];

        // Center Demonic Eye with Pupil Slit
        UIBezierPath* eye = [UIBezierPath bezierPath];
        [eye moveToPoint:CGPointMake(cx - w * 0.15f, cy)];
        [eye addQuadCurveToPoint:CGPointMake(cx + w * 0.15f, cy) controlPoint:CGPointMake(cx, cy - h * 0.12f)];
        [eye addQuadCurveToPoint:CGPointMake(cx - w * 0.15f, cy) controlPoint:CGPointMake(cx, cy + h * 0.12f)];
        [eye closePath];
        eye.lineWidth = 1.8f;
        [eye stroke];

        UIBezierPath* pupil = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - 2.5f, cy - h * 0.08f, 5.0f, h * 0.16f)];
        [pupil fill];
    });
}

// 7. Devil Trigger: Horned Demonic Visage (Nero Stand / Dante DT)
UIImage* CreateDevilTriggerIcon(CGFloat size, UIColor* tint) {
    return RenderIcon(CGSizeMake(size, size), ^(CGContextRef ctx, CGRect rect) {
        CGFloat w = rect.size.width;
        CGFloat h = rect.size.height;
        CGFloat cx = w / 2.0f;
        CGFloat cy = h / 2.0f;

        [tint setStroke];
        [tint setFill];

        UIBezierPath* horns = [UIBezierPath bezierPath];
        [horns moveToPoint:CGPointMake(cx, cy + h * 0.34f)]; // Chin point
        [horns addLineToPoint:CGPointMake(cx - w * 0.22f, cy + h * 0.12f)]; // Jaw left
        [horns addQuadCurveToPoint:CGPointMake(cx - w * 0.38f, cy - h * 0.38f) // Left sweeping horn tip
                      controlPoint:CGPointMake(cx - w * 0.34f, cy - h * 0.10f)];
        [horns addQuadCurveToPoint:CGPointMake(cx - w * 0.12f, cy - h * 0.12f) // Forehead crest
                      controlPoint:CGPointMake(cx - w * 0.18f, cy - h * 0.20f)];
        [horns addLineToPoint:CGPointMake(cx, cy - h * 0.24f)]; // Center crown point
        [horns addLineToPoint:CGPointMake(cx + w * 0.12f, cy - h * 0.12f)];
        [horns addQuadCurveToPoint:CGPointMake(cx + w * 0.38f, cy - h * 0.38f) // Right sweeping horn tip
                      controlPoint:CGPointMake(cx + w * 0.18f, cy - h * 0.20f)];
        [horns addQuadCurveToPoint:CGPointMake(cx + w * 0.22f, cy + h * 0.12f) // Jaw right
                      controlPoint:CGPointMake(cx + w * 0.34f, cy - h * 0.10f)];
        [horns closePath];

        horns.lineWidth = 1.8f;
        [horns stroke];
        CGContextSetAlpha(ctx, 0.45f);
        [horns fill];

        // Burning Demonic Visor Eye Slits
        CGContextSetAlpha(ctx, 1.0f);
        UIBezierPath* eyes = [UIBezierPath bezierPath];
        [eyes moveToPoint:CGPointMake(cx - w * 0.16f, cy - h * 0.02f)];
        [eyes addLineToPoint:CGPointMake(cx - w * 0.04f, cy + h * 0.04f)];
        [eyes moveToPoint:CGPointMake(cx + w * 0.16f, cy - h * 0.02f)];
        [eyes addLineToPoint:CGPointMake(cx + w * 0.04f, cy + h * 0.04f)];
        eyes.lineWidth = 2.2f;
        [eyes stroke];
    });
}

// 8. Dante Styles: Trickster, Swordmaster, Gunslinger, Royalguard
UIImage* CreateStyleGlyphIcon(char styleChar, CGFloat size, UIColor* tint) {
    return RenderIcon(CGSizeMake(size, size), ^(CGContextRef ctx, CGRect rect) {
        CGFloat w = rect.size.width;
        CGFloat h = rect.size.height;
        CGFloat cx = w / 2.0f;
        CGFloat cy = h / 2.0f;

        [tint setStroke];
        [tint setFill];

        if (styleChar == 'T') {
            // Trickster Dash: Running shadow with speed lines
            UIBezierPath* dash = [UIBezierPath bezierPath];
            [dash moveToPoint:CGPointMake(cx - w * 0.28f, cy + h * 0.20f)];
            [dash addLineToPoint:CGPointMake(cx + w * 0.26f, cy + h * 0.20f)];
            [dash addLineToPoint:CGPointMake(cx + w * 0.14f, cy - h * 0.20f)];
            [dash addLineToPoint:CGPointMake(cx - w * 0.06f, cy - h * 0.20f)];
            [dash closePath];
            dash.lineWidth = 2.0f;
            [dash stroke];
            CGContextSetAlpha(ctx, 0.4f);
            [dash fill];

            CGContextSetAlpha(ctx, 1.0f);
            UIBezierPath* streaks = [UIBezierPath bezierPath];
            [streaks moveToPoint:CGPointMake(cx - w * 0.38f, cy - h * 0.10f)];
            [streaks addLineToPoint:CGPointMake(cx - w * 0.14f, cy - h * 0.10f)];
            [streaks moveToPoint:CGPointMake(cx - w * 0.42f, cy + h * 0.05f)];
            [streaks addLineToPoint:CGPointMake(cx - w * 0.10f, cy + h * 0.05f)];
            streaks.lineWidth = 1.8f;
            [streaks stroke];
        } else if (styleChar == 'S') {
            // Swordmaster: Crossed Rebellion Blades
            UIBezierPath* s1 = [UIBezierPath bezierPath];
            [s1 moveToPoint:CGPointMake(cx - w * 0.28f, cy - h * 0.28f)];
            [s1 addLineToPoint:CGPointMake(cx + w * 0.28f, cy + h * 0.28f)];
            s1.lineWidth = 2.6f;
            [s1 stroke];

            UIBezierPath* s2 = [UIBezierPath bezierPath];
            [s2 moveToPoint:CGPointMake(cx + w * 0.28f, cy - h * 0.28f)];
            [s2 addLineToPoint:CGPointMake(cx - w * 0.28f, cy + h * 0.28f)];
            s2.lineWidth = 2.6f;
            [s2 stroke];

            UIBezierPath* slash = [UIBezierPath bezierPathWithArcCenter:CGPointMake(cx, cy) radius:w * 0.36f startAngle:M_PI * 0.2f endAngle:M_PI * 0.8f clockwise:YES];
            slash.lineWidth = 1.6f;
            [slash stroke];
        } else if (styleChar == 'G') {
            // Gunslinger: Crossed Pistols (Ebony & Ivory)
            UIBezierPath* g1 = [UIBezierPath bezierPath];
            [g1 moveToPoint:CGPointMake(cx - w * 0.30f, cy)];
            [g1 addLineToPoint:CGPointMake(cx + w * 0.30f, cy)];
            [g1 moveToPoint:CGPointMake(cx, cy - h * 0.30f)];
            [g1 addLineToPoint:CGPointMake(cx, cy + h * 0.30f)];
            g1.lineWidth = 2.2f;
            [g1 stroke];

            UIBezierPath* circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(cx - w * 0.18f, cy - h * 0.18f, w * 0.36f, h * 0.36f)];
            circle.lineWidth = 1.8f;
            [circle stroke];
        } else if (styleChar == 'R') {
            // Royalguard: Aegis Barrier Spiked Shield
            UIBezierPath* shield = [UIBezierPath bezierPath];
            [shield moveToPoint:CGPointMake(cx, cy - h * 0.32f)];
            [shield addLineToPoint:CGPointMake(cx + w * 0.28f, cy - h * 0.18f)];
            [shield addLineToPoint:CGPointMake(cx + w * 0.22f, cy + h * 0.12f)];
            [shield addQuadCurveToPoint:CGPointMake(cx, cy + h * 0.34f) controlPoint:CGPointMake(cx + w * 0.10f, cy + h * 0.28f)];
            [shield addQuadCurveToPoint:CGPointMake(cx - w * 0.22f, cy + h * 0.12f) controlPoint:CGPointMake(cx - w * 0.10f, cy + h * 0.28f)];
            [shield addLineToPoint:CGPointMake(cx - w * 0.28f, cy - h * 0.18f)];
            [shield closePath];
            shield.lineWidth = 2.2f;
            [shield stroke];
            CGContextSetAlpha(ctx, 0.45f);
            [shield fill];
        }
    });
}

} // namespace dmc4::icons

// ---------------------------------------------------------------------------
//  Always-On-Top Passthrough Container View
// ---------------------------------------------------------------------------

@interface TouchOverlayContainerView : UIView
@property (nonatomic, assign) BOOL allowPassthrough;
@end

@implementation TouchOverlayContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.zPosition = 9999.0f;
        self.multipleTouchEnabled = YES;
        self.userInteractionEnabled = YES;
        self.allowPassthrough = YES;
    }
    return self;
}

- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    if (hit == self && self.allowPassthrough) {
        return nil;
    }
    return hit;
}

@end

// ---------------------------------------------------------------------------
//  Interactive DMC4 Combat Action Button Component
// ---------------------------------------------------------------------------

@interface DMC4CombatButton : UIControl
@property (nonatomic, strong) UIImageView* iconImageView;
@property (nonatomic, strong) UILabel* nameLabel;
@property (nonatomic, strong) UILabel* keyBadgeLabel;
@property (nonatomic, strong) CAShapeLayer* glowBorder;
@property (nonatomic, strong) CAShapeLayer* innerBevel;
@property (nonatomic, strong) CAShapeLayer* haloChargeRing;
@property (nonatomic, strong) UIColor* themeColor;
@property (nonatomic, assign) BOOL isChargingActive;

- (instancetype)initWithFrame:(CGRect)frame
                         icon:(UIImage*)icon
                        title:(NSString*)title
                     keyBadge:(NSString*)keyBadge
                        color:(UIColor*)color;
- (void)setHighlighted:(BOOL)highlighted;
- (void)pulseChargingHalo:(BOOL)charging;
@end

@implementation DMC4CombatButton

- (instancetype)initWithFrame:(CGRect)frame
                         icon:(UIImage*)icon
                        title:(NSString*)title
                     keyBadge:(NSString*)keyBadge
                        color:(UIColor*)color {
    if (self = [super initWithFrame:frame]) {
        _themeColor = color;
        CGFloat sz = frame.size.width;

        self.backgroundColor = [UIColor colorWithRed:0.06f green:0.07f blue:0.10f alpha:0.78f];
        self.layer.cornerRadius = sz / 2.0f;
        self.layer.masksToBounds = NO;

        // Glowing outer Gothic border
        _glowBorder = [CAShapeLayer layer];
        _glowBorder.path = [UIBezierPath bezierPathWithOvalInRect:self.bounds].CGPath;
        _glowBorder.fillColor = [UIColor clearColor].CGColor;
        _glowBorder.strokeColor = color.CGColor;
        _glowBorder.lineWidth = 2.4f;
        _glowBorder.shadowColor = color.CGColor;
        _glowBorder.shadowRadius = 8.0f;
        _glowBorder.shadowOpacity = 0.90f;
        _glowBorder.shadowOffset = CGSizeZero;
        [self.layer addSublayer:_glowBorder];

        // Inner beveled metal ring
        _innerBevel = [CAShapeLayer layer];
        _innerBevel.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 3.5f, 3.5f)].CGPath;
        _innerBevel.fillColor = [UIColor clearColor].CGColor;
        _innerBevel.strokeColor = [UIColor colorWithWhite:1.0f alpha:0.25f].CGColor;
        _innerBevel.lineWidth = 1.0f;
        [self.layer addSublayer:_innerBevel];

        // Procedural Vector Icon
        _iconImageView = [[UIImageView alloc] initWithImage:icon];
        _iconImageView.frame = CGRectMake(sz * 0.16f, sz * 0.10f, sz * 0.68f, sz * 0.56f);
        _iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        _iconImageView.tintColor = [UIColor whiteColor];
        _iconImageView.userInteractionEnabled = NO;
        [self addSubview:_iconImageView];

        // Action Name Label
        _nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(2, sz * 0.66f, sz - 4, 15)];
        _nameLabel.text = title;
        _nameLabel.textColor = [UIColor whiteColor];
        _nameLabel.font = [UIFont systemFontOfSize:9.5f weight:UIFontWeightHeavy];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.userInteractionEnabled = NO;
        [self addSubview:_nameLabel];

        // Xbox Controller Key Badge Pill (Y, B, A, X, LT, RB, LB)
        if (keyBadge.length > 0) {
            _keyBadgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(sz - 26, 0, 24, 16)];
            _keyBadgeLabel.text = keyBadge;
            _keyBadgeLabel.textColor = [UIColor whiteColor];
            _keyBadgeLabel.backgroundColor = [color colorWithAlphaComponent:0.95f];
            _keyBadgeLabel.font = [UIFont systemFontOfSize:9.0f weight:UIFontWeightBold];
            _keyBadgeLabel.textAlignment = NSTextAlignmentCenter;
            _keyBadgeLabel.layer.cornerRadius = 8.0f;
            _keyBadgeLabel.layer.masksToBounds = YES;
            _keyBadgeLabel.layer.borderColor = [UIColor whiteColor].CGColor;
            _keyBadgeLabel.layer.borderWidth = 1.0f;
            _keyBadgeLabel.userInteractionEnabled = NO;
            [self addSubview:_keyBadgeLabel];
        }
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        if (highlighted) {
            self.transform = CGAffineTransformMakeScale(0.88f, 0.88f);
            self.backgroundColor = [self.themeColor colorWithAlphaComponent:0.60f];
            self.glowBorder.lineWidth = 3.6f;
            self.glowBorder.shadowRadius = 14.0f;
        } else {
            self.transform = CGAffineTransformIdentity;
            self.backgroundColor = [UIColor colorWithRed:0.06f green:0.07f blue:0.10f alpha:0.78f];
            self.glowBorder.lineWidth = 2.4f;
            self.glowBorder.shadowRadius = 8.0f;
        }
    } completion:nil];
}

- (void)pulseChargingHalo:(BOOL)charging {
    _isChargingActive = charging;
    if (charging) {
        if (!_haloChargeRing) {
            _haloChargeRing = [CAShapeLayer layer];
            CGRect ringRect = CGRectInset(self.bounds, -8, -8);
            _haloChargeRing.path = [UIBezierPath bezierPathWithOvalInRect:ringRect].CGPath;
            _haloChargeRing.fillColor = [UIColor clearColor].CGColor;
            _haloChargeRing.strokeColor = [UIColor colorWithRed:1.0f green:0.85f blue:0.0f alpha:1.0f].CGColor;
            _haloChargeRing.lineWidth = 3.2f;
            _haloChargeRing.lineDashPattern = @[@8, @4];
            [self.layer addSublayer:_haloChargeRing];

            CABasicAnimation* rotate = [CABasicAnimation animationWithKeyPath:@"transform.rotation"];
            rotate.fromValue = @0;
            rotate.toValue = @(M_PI * 2.0);
            rotate.duration = 1.2;
            rotate.repeatCount = HUGE_VALF;
            [_haloChargeRing addAnimation:rotate forKey:@"chargeRotate"];
        }
        _haloChargeRing.hidden = NO;
    } else if (_haloChargeRing) {
        _haloChargeRing.hidden = YES;
    }
}

@end

// ---------------------------------------------------------------------------
//  DMC4 Combat HUD Overlay Controller
// ---------------------------------------------------------------------------

@interface DMC4TouchOverlayViewController : UIViewController {
    TouchOverlayContainerView* _container;
    dmc4::touch::TouchSettings _settings;

    // Left Thumb Controls (Dynamic Floating 360 Stick)
    UIView* _stickBase;
    UIView* _stickThumb;
    CGPoint _stickCenter;
    BOOL _stickActive;
    UITouch* _stickTouch;

    // Stylish Combat Action Cluster (Right Thumb Ergonomic Arc)
    DMC4CombatButton* _btnMelee;       // Y - Red Queen / Rebellion
    DMC4CombatButton* _btnBringer;     // B - Devil Bringer / Buster / Snatch
    DMC4CombatButton* _btnJump;        // A - Jump / Evade / Air Hike
    DMC4CombatButton* _btnShoot;       // X - Blue Rose / Ebony & Ivory
    DMC4CombatButton* _btnExceed;      // LT - Nero MAX-Act / Instant Rev
    DMC4CombatButton* _btnLockOn;      // RB - Smart Lock-On (1-Tap Toggle)
    DMC4CombatButton* _btnDevilTrigger;// LB - Devil Trigger (Nero Stand / Dante DT)
    DMC4CombatButton* _btnTaunt;       // Back - Taunt

    // Dante 4-Style Quick Cross
    UIView* _styleCrossContainer;
    UIButton* _btnTrickster;
    UIButton* _btnSwordmaster;
    UIButton* _btnGunslinger;
    UIButton* _btnRoyalguard;

    // Right-Screen Virtual Camera Pan Zone
    UIPanGestureRecognizer* _cameraPanGesture;
    UITapGestureRecognizer* _cameraResetTap;
    CGPoint _lastPanLocation;

    // Top Bar Control HUD
    UIView* _topBarHUD;
    UILabel* _fpsLabel;
    UISegmentedControl* _modeSegment;
    UIButton* _btnGear;
    UIButton* _btnResetCamera;

    // State & Gestures
    BOOL _lockOnLatched;
    BOOL _chargeShotLatched;
    BOOL _hudHidden;
    CGPoint _meleeTouchStart;
    CGPoint _bringerTouchStart;
    NSTimeInterval _lastShootTapTime;

    // Haptics
    UIImpactFeedbackGenerator* _lightHaptic;
    UIImpactFeedbackGenerator* _rigidHaptic;
}

- (void)updateLayout;
- (void)applySettings:(const dmc4::touch::TouchSettings&)settings;
- (void)bringToFront;

@end

@implementation DMC4TouchOverlayViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    _container = [[TouchOverlayContainerView alloc] initWithFrame:self.view.bounds];
    _container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_container];

    _lightHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    _rigidHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
    [_lightHaptic prepare];
    [_rigidHaptic prepare];

    _settings = dmc4::touch::GetCurrentSettings();

    [self setupControls];
    [self setupCameraGestures];
    [self setupControllerNotifications];
    [self updateLayout];
}

- (void)setupControls {
    // -----------------------------------------------------------------------
    // 1. Left Thumb Dynamic Floating 360-Degree Joystick
    // -----------------------------------------------------------------------
    _stickBase = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 160, 160)];
    _stickBase.backgroundColor = [UIColor colorWithRed:0.06f green:0.08f blue:0.12f alpha:0.55f];
    _stickBase.layer.cornerRadius = 80.0f;
    _stickBase.layer.borderColor = [UIColor colorWithRed:0.0f green:0.85f blue:1.0f alpha:0.75f].CGColor;
    _stickBase.layer.borderWidth = 2.2f;
    _stickBase.userInteractionEnabled = NO;
    [_container addSubview:_stickBase];

    _stickThumb = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 72, 72)];
    _stickThumb.backgroundColor = [UIColor colorWithRed:0.0f green:0.82f blue:1.0f alpha:0.85f];
    _stickThumb.layer.cornerRadius = 36.0f;
    _stickThumb.layer.borderColor = [UIColor whiteColor].CGColor;
    _stickThumb.layer.borderWidth = 2.2f;
    _stickThumb.layer.shadowColor = [UIColor colorWithRed:0.0f green:0.85f blue:1.0f alpha:1.0f].CGColor;
    _stickThumb.layer.shadowRadius = 8.0f;
    _stickThumb.layer.shadowOpacity = 0.9f;
    _stickThumb.userInteractionEnabled = NO;
    [_container addSubview:_stickThumb];

    // -----------------------------------------------------------------------
    // 2. Right Thumb Action Cluster (Ergonomic Thumb Arc)
    // -----------------------------------------------------------------------

    // Melee (Y) - Primary Oversized Crimson Broadsword
    UIImage* meleeIcon = dmc4::icons::CreateMeleeSwordIcon(54.0f, [UIColor colorWithRed:1.0f green:0.25f blue:0.35f alpha:1.0f]);
    _btnMelee = [[DMC4CombatButton alloc] initWithFrame:CGRectMake(0, 0, 96, 96)
                                                   icon:meleeIcon
                                                  title:@"MELEE"
                                               keyBadge:@"Y"
                                                  color:[UIColor colorWithRed:1.0f green:0.15f blue:0.30f alpha:1.0f]];
    [_btnMelee addTarget:self action:@selector(onMeleeDown:withEvent:) forControlEvents:UIControlEventTouchDown];
    [_btnMelee addTarget:self action:@selector(onMeleeUp:withEvent:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_btnMelee addTarget:self action:@selector(onMeleeDragExit:withEvent:) forControlEvents:UIControlEventTouchDragExit];
    [_container addSubview:_btnMelee];

    // Devil Bringer / Buster (B) - Spectral Neon Cyan Demonic Arm
    UIImage* bringerIcon = dmc4::icons::CreateDevilBringerClawIcon(48.0f, [UIColor colorWithRed:0.0f green:0.90f blue:1.0f alpha:1.0f]);
    _btnBringer = [[DMC4CombatButton alloc] initWithFrame:CGRectMake(0, 0, 84, 84)
                                                     icon:bringerIcon
                                                    title:@"BRINGER"
                                                 keyBadge:@"B"
                                                    color:[UIColor colorWithRed:0.0f green:0.85f blue:1.0f alpha:1.0f]];
    [_btnBringer addTarget:self action:@selector(onBringerDown:withEvent:) forControlEvents:UIControlEventTouchDown];
    [_btnBringer addTarget:self action:@selector(onBringerUp:withEvent:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_container addSubview:_btnBringer];

    // Jump / Air Hike (A) - Emerald Wing Crest
    UIImage* jumpIcon = dmc4::icons::CreateJumpWingsIcon(46.0f, [UIColor colorWithRed:0.20f green:0.95f blue:0.45f alpha:1.0f]);
    _btnJump = [[DMC4CombatButton alloc] initWithFrame:CGRectMake(0, 0, 82, 82)
                                                  icon:jumpIcon
                                                 title:@"JUMP"
                                              keyBadge:@"A"
                                                 color:[UIColor colorWithRed:0.15f green:0.90f blue:0.40f alpha:1.0f]];
    [_btnJump addTarget:self action:@selector(onJumpDown) forControlEvents:UIControlEventTouchDown];
    [_btnJump addTarget:self action:@selector(onJumpUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_container addSubview:_btnJump];

    // Shoot (X) - Blue Rose Twin-Barrel Revolver (Cobalt)
    UIImage* shootIcon = dmc4::icons::CreateShootGunIcon(46.0f, [UIColor colorWithRed:0.25f green:0.65f blue:1.0f alpha:1.0f]);
    _btnShoot = [[DMC4CombatButton alloc] initWithFrame:CGRectMake(0, 0, 82, 82)
                                                   icon:shootIcon
                                                  title:@"SHOOT"
                                               keyBadge:@"X"
                                                  color:[UIColor colorWithRed:0.20f green:0.60f blue:1.0f alpha:1.0f]];
    [_btnShoot addTarget:self action:@selector(onShootDown) forControlEvents:UIControlEventTouchDown];
    [_btnShoot addTarget:self action:@selector(onShootUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_container addSubview:_btnShoot];

    // Exceed Rev (LT) - Tachometer & 3-Flame Rev Gauge (Fiery Amber)
    // Placed directly above Melee (Y) so thumb-sliding triggers MAX-Act effortlessly!
    UIImage* exceedIcon = dmc4::icons::CreateExceedRevIcon(50.0f, [UIColor colorWithRed:1.0f green:0.65f blue:0.0f alpha:1.0f]);
    _btnExceed = [[DMC4CombatButton alloc] initWithFrame:CGRectMake(0, 0, 88, 88)
                                                    icon:exceedIcon
                                                   title:@"EXCEED"
                                                keyBadge:@"LT"
                                                   color:[UIColor colorWithRed:1.0f green:0.55f blue:0.0f alpha:1.0f]];
    [_btnExceed addTarget:self action:@selector(onExceedDown) forControlEvents:UIControlEventTouchDown];
    [_btnExceed addTarget:self action:@selector(onExceedUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_container addSubview:_btnExceed];

    // Smart Lock-On (RB) - Demonic Eye Target Reticle (Amethyst)
    UIImage* lockOnIcon = dmc4::icons::CreateLockOnReticleIcon(46.0f, [UIColor colorWithRed:0.85f green:0.30f blue:1.0f alpha:1.0f]);
    _btnLockOn = [[DMC4CombatButton alloc] initWithFrame:CGRectMake(0, 0, 80, 80)
                                                    icon:lockOnIcon
                                                   title:@"LOCK-ON"
                                                keyBadge:@"RB"
                                                   color:[UIColor colorWithRed:0.75f green:0.20f blue:0.95f alpha:1.0f]];
    [_btnLockOn addTarget:self action:@selector(onLockOnTapped) forControlEvents:UIControlEventTouchUpInside];
    [_btnLockOn addTarget:self action:@selector(onLockOnHoldDown) forControlEvents:UIControlEventTouchDown];
    [_btnLockOn addTarget:self action:@selector(onLockOnHoldUp) forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_container addSubview:_btnLockOn];

    // Devil Trigger (LB) - Demonic Horned Visage
    UIImage* dtIcon = dmc4::icons::CreateDevilTriggerIcon(40.0f, [UIColor colorWithRed:1.0f green:0.20f blue:0.20f alpha:1.0f]);
    _btnDevilTrigger = [[DMC4CombatButton alloc] initWithFrame:CGRectMake(0, 0, 70, 70)
                                                         icon:dtIcon
                                                        title:@"DT"
                                                     keyBadge:@"LB"
                                                        color:[UIColor colorWithRed:0.95f green:0.10f blue:0.20f alpha:1.0f]];
    [_btnDevilTrigger addTarget:self action:@selector(onDTDown) forControlEvents:UIControlEventTouchDown];
    [_btnDevilTrigger addTarget:self action:@selector(onDTUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_container addSubview:_btnDevilTrigger];

    // Taunt (Back)
    _btnTaunt = [[DMC4CombatButton alloc] initWithFrame:CGRectMake(0, 0, 62, 62)
                                                   icon:nil
                                                  title:@"TAUNT"
                                               keyBadge:@"SEL"
                                                  color:[UIColor colorWithWhite:0.35f alpha:1.0f]];
    [_btnTaunt addTarget:self action:@selector(onTauntDown) forControlEvents:UIControlEventTouchDown];
    [_btnTaunt addTarget:self action:@selector(onTauntUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_container addSubview:_btnTaunt];

    // -----------------------------------------------------------------------
    // 3. Dante 4-Style Quick Cross
    // -----------------------------------------------------------------------
    _styleCrossContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 144, 144)];
    _styleCrossContainer.backgroundColor = [UIColor colorWithWhite:0.08f alpha:0.60f];
    _styleCrossContainer.layer.cornerRadius = 72.0f;
    _styleCrossContainer.layer.borderColor = [UIColor colorWithRed:0.9f green:0.2f blue:0.2f alpha:0.55f].CGColor;
    _styleCrossContainer.layer.borderWidth = 1.8f;
    [_container addSubview:_styleCrossContainer];

    _btnTrickster = [self createDanteStyleButton:'T' title:@"TRICK" color:[UIColor colorWithRed:1.0f green:0.85f blue:0.1f alpha:1.0f] bitmask:kUp];
    _btnSwordmaster = [self createDanteStyleButton:'S' title:@"SWORD" color:[UIColor colorWithRed:1.0f green:0.15f blue:0.25f alpha:1.0f] bitmask:kRight];
    _btnGunslinger = [self createDanteStyleButton:'G' title:@"GUN" color:[UIColor colorWithRed:0.1f green:0.75f blue:1.0f alpha:1.0f] bitmask:kLeft];
    _btnRoyalguard = [self createDanteStyleButton:'R' title:@"GUARD" color:[UIColor colorWithRed:0.75f green:0.15f blue:1.0f alpha:1.0f] bitmask:kDown];

    [_styleCrossContainer addSubview:_btnTrickster];
    [_styleCrossContainer addSubview:_btnSwordmaster];
    [_styleCrossContainer addSubview:_btnGunslinger];
    [_styleCrossContainer addSubview:_btnRoyalguard];

    // -----------------------------------------------------------------------
    // 4. Top Bar HUD & Live Controls
    // -----------------------------------------------------------------------
    _topBarHUD = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 470, 42)];
    _topBarHUD.backgroundColor = [UIColor colorWithRed:0.06f green:0.07f blue:0.10f alpha:0.85f];
    _topBarHUD.layer.cornerRadius = 21.0f;
    _topBarHUD.layer.borderColor = [UIColor colorWithWhite:0.35f alpha:0.7f].CGColor;
    _topBarHUD.layer.borderWidth = 1.2f;
    [_container addSubview:_topBarHUD];

    _fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 6, 75, 30)];
    _fpsLabel.text = @"60 FPS";
    _fpsLabel.textColor = [UIColor colorWithRed:0.2f green:1.0f blue:0.4f alpha:1.0f];
    _fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0f weight:UIFontWeightBold];
    [_topBarHUD addSubview:_fpsLabel];

    _modeSegment = [[UISegmentedControl alloc] initWithItems:@[@"NERO", @"DANTE", @"EXPLORE", @"HIDE"]];
    _modeSegment.frame = CGRectMake(95, 6, 200, 30);
    _modeSegment.selectedSegmentIndex = 0;
    [_modeSegment addTarget:self action:@selector(onModeChanged:) forControlEvents:UIControlEventValueChanged];
    [_topBarHUD addSubview:_modeSegment];

    _btnResetCamera = [UIButton buttonWithType:UIButtonTypeSystem];
    _btnResetCamera.frame = CGRectMake(305, 6, 80, 30);
    [_btnResetCamera setTitle:@"CAM (RS)" forState:UIControlStateNormal];
    [_btnResetCamera setTitleColor:[UIColor colorWithRed:0.8f green:0.9f blue:1.0f alpha:1.0f] forState:UIControlStateNormal];
    _btnResetCamera.titleLabel.font = [UIFont systemFontOfSize:11.5f weight:UIFontWeightBold];
    [_btnResetCamera addTarget:self action:@selector(onResetCamTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topBarHUD addSubview:_btnResetCamera];

    _btnGear = [UIButton buttonWithType:UIButtonTypeSystem];
    _btnGear.frame = CGRectMake(390, 6, 70, 30);
    [_btnGear setTitle:@"GEAR ⚙" forState:UIControlStateNormal];
    [_btnGear setTitleColor:[UIColor colorWithRed:1.0f green:0.85f blue:0.2f alpha:1.0f] forState:UIControlStateNormal];
    _btnGear.titleLabel.font = [UIFont systemFontOfSize:12.0f weight:UIFontWeightHeavy];
    [_btnGear addTarget:self action:@selector(onGearTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topBarHUD addSubview:_btnGear];
}

- (void)setupCameraGestures {
    _cameraPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onCameraPan:)];
    _cameraPanGesture.cancelsTouchesInView = NO;
    _cameraPanGesture.maximumNumberOfTouches = 1;
    [self.view addGestureRecognizer:_cameraPanGesture];

    _cameraResetTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onCameraResetDoubleTap:)];
    _cameraResetTap.numberOfTapsRequired = 2;
    _cameraResetTap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:_cameraResetTap];
}

- (void)onCameraPan:(UIPanGestureRecognizer*)pan {
    if (!_settings.cameraPanZoneEnabled) return;
    CGPoint pt = [pan locationInView:self.view];

    // Active in upper/middle right region of screen (away from buttons)
    if (pan.state == UIGestureRecognizerStateBegan) {
        if (pt.x > self.view.bounds.size.width * 0.45f && pt.y < self.view.bounds.size.height * 0.70f) {
            _lastPanLocation = pt;
        } else {
            pan.state = UIGestureRecognizerStateCancelled;
        }
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self.view];
        CGFloat sens = 450.0;
        CGFloat valX = translation.x * sens;
        CGFloat valY = translation.y * sens;
        CGFloat clampedX = std::clamp<CGFloat>(valX, -32767.0, 32767.0);
        CGFloat clampedY = std::clamp<CGFloat>(valY, -32767.0, 32767.0);
        Sint16 rx = static_cast<Sint16>(clampedX);
        Sint16 ry = static_cast<Sint16>(clampedY);
        SetAxisValue(2, rx);
        SetAxisValue(3, ry);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        SetAxisValue(2, 0);
        SetAxisValue(3, 0);
    }
}

- (void)onCameraResetDoubleTap:(UITapGestureRecognizer*)tap {
    CGPoint pt = [tap locationInView:self.view];
    if (pt.x > self.view.bounds.size.width * 0.45f && pt.y < self.view.bounds.size.height * 0.70f) {
        [self onResetCamTapped];
    }
}

- (UIButton*)createDanteStyleButton:(char)styleChar title:(NSString*)title color:(UIColor*)color bitmask:(int)bitmask {
    UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, 44, 44);
    btn.backgroundColor = [UIColor colorWithWhite:0.10f alpha:0.85f];
    btn.layer.cornerRadius = 22.0f;
    btn.layer.borderColor = color.CGColor;
    btn.layer.borderWidth = 1.8f;
    btn.tag = bitmask;

    UIImage* glyph = dmc4::icons::CreateStyleGlyphIcon(styleChar, 26.0f, color);
    [btn setImage:glyph forState:UIControlStateNormal];
    btn.tintColor = color;

    [btn addTarget:self action:@selector(onStyleDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(onStyleUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return btn;
}

- (void)updateLayout {
    CGSize sz = self.view.bounds.size;
    BOOL isPad = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
    CGFloat scale = _settings.buttonScale * (isPad ? 1.25f : 1.0f);
    CGFloat pad = isPad ? 44.0f : 24.0f;

    // Left Thumb Analog Stick
    _stickCenter = CGPointMake(pad + 85.0f, sz.height - pad - 85.0f);
    _stickBase.center = _stickCenter;
    _stickThumb.center = _stickCenter;

    // Dante 4-Style Quick Cross (Left side, comfortably above stick)
    _styleCrossContainer.center = CGPointMake(pad + 85.0f, sz.height - pad - 235.0f);
    _btnTrickster.center = CGPointMake(72, 26);
    _btnSwordmaster.center = CGPointMake(118, 72);
    _btnGunslinger.center = CGPointMake(26, 72);
    _btnRoyalguard.center = CGPointMake(72, 118);

    // Ergonomic Right Thumb Arc Cluster (Rotates with natural thumb sweep)
    CGFloat anchorX = sz.width - pad - 95.0f;
    CGFloat anchorY = sz.height - pad - 95.0f;

    _btnMelee.center = CGPointMake(anchorX - 30.0f * scale, anchorY - 65.0f * scale);
    _btnBringer.center = CGPointMake(anchorX + 48.0f * scale, anchorY - 20.0f * scale);
    _btnJump.center = CGPointMake(anchorX - 30.0f * scale, anchorY + 35.0f * scale);
    _btnShoot.center = CGPointMake(anchorX - 105.0f * scale, anchorY - 20.0f * scale);

    // Exceed Rev (LT) directly above Melee (Y) for instant thumb-slide MAX-Act!
    _btnExceed.center = CGPointMake(anchorX - 30.0f * scale, anchorY - 165.0f * scale);

    // Smart Lock-On (RB) above Bringer (B)
    _btnLockOn.center = CGPointMake(anchorX + 58.0f * scale, anchorY - 110.0f * scale);

    // Devil Trigger (LB) & Taunt (Back)
    _btnDevilTrigger.center = CGPointMake(anchorX - 115.0f * scale, anchorY - 110.0f * scale);
    _btnTaunt.center = CGPointMake(anchorX - 185.0f * scale, anchorY - 40.0f * scale);

    // Top Bar HUD
    _topBarHUD.center = CGPointMake(sz.width / 2.0f, 32.0f);

    _container.alpha = _settings.opacity;
    _styleCrossContainer.hidden = !_settings.danteStyleCrossVisible;
}

- (void)bringToFront {
    if (_container) {
        [_container.superview bringSubviewToFront:_container];
        _container.layer.zPosition = 9999.0f;
    }
}

- (void)applySettings:(const dmc4::touch::TouchSettings&)settings {
    _settings = settings;
    [self updateLayout];
}

// ---------------------------------------------------------------------------
//  Dynamic Floating Stick Gesture (Left Screen Half)
// ---------------------------------------------------------------------------

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    for (UITouch* t in touches) {
        CGPoint pt = [t locationInView:_container];
        if (pt.x < self.view.bounds.size.width * 0.45f && pt.y > 70.0f) {
            _stickTouch = t;
            _stickActive = YES;
            // Float stick base directly to touch position
            _stickCenter = pt;
            _stickBase.center = pt;
            _stickThumb.center = pt;
            break;
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if (!_stickActive || !_stickTouch) return;
    for (UITouch* t in touches) {
        if (t == _stickTouch) {
            CGPoint pt = [t locationInView:_container];
            CGFloat dx = pt.x - _stickCenter.x;
            CGFloat dy = pt.y - _stickCenter.y;
            CGFloat dist = std::hypot(dx, dy);
            CGFloat maxR = 60.0f;

            if (dist > maxR) {
                dx = (dx / dist) * maxR;
                dy = (dy / dist) * maxR;
            }
            _stickThumb.center = CGPointMake(_stickCenter.x + dx, _stickCenter.y + dy);

            // Normalized axes output (-32768 to 32767)
            Sint16 axisX = static_cast<Sint16>((dx / maxR) * 32767.0f);
            Sint16 axisY = static_cast<Sint16>((dy / maxR) * 32767.0f);
            SetAxisValue(0, axisX);
            SetAxisValue(1, axisY);
            break;
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    for (UITouch* t in touches) {
        if (t == _stickTouch) {
            _stickActive = NO;
            _stickTouch = nil;
            _stickThumb.center = _stickCenter;
            SetAxisValue(0, 0);
            SetAxisValue(1, 0);
            break;
        }
    }
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self touchesEnded:touches withEvent:event];
}

// ---------------------------------------------------------------------------
//  Nero Combat Gestures: Melee Directional Gestures & Exceed MAX-Act Rev
// ---------------------------------------------------------------------------

- (void)onMeleeDown:(UIButton*)sender withEvent:(UIEvent*)event {
    UITouch* touch = [[event allTouches] anyObject];
    if (touch) {
        _meleeTouchStart = [touch locationInView:_container];
    }
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit(kY, true);
}

- (void)onMeleeUp:(UIButton*)sender withEvent:(UIEvent*)event {
    UITouch* touch = [[event allTouches] anyObject];
    if (touch && _settings.combatGesturesEnabled) {
        CGPoint pt = [touch locationInView:_container];
        CGFloat dy = pt.y - _meleeTouchStart.y;
        if (dy < -35.0f) {
            // Swipe UP on Melee -> Streak / Stinger! (Lock-On + Forward + Y)
            if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
            SetButtonBit(kRB, true);
            SetAxisValue(1, -32767); // Forward
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SetAxisValue(1, 0);
                if (_settings.lockOn != dmc4::touch::LockOnMode::Toggle || !_lockOnLatched) {
                    SetButtonBit(kRB, false);
                }
            });
        } else if (dy > 35.0f) {
            // Swipe DOWN on Melee -> High Time launcher! (Lock-On + Back + Y)
            if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
            SetButtonBit(kRB, true);
            SetAxisValue(1, 32767); // Backward
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SetAxisValue(1, 0);
                if (_settings.lockOn != dmc4::touch::LockOnMode::Toggle || !_lockOnLatched) {
                    SetButtonBit(kRB, false);
                }
            });
        }
    }
    SetButtonBit(kY, false);
}

- (void)onMeleeDragExit:(UIButton*)sender withEvent:(UIEvent*)event {
    // Detect if thumb dragged upwards toward Exceed (LT)
    UITouch* touch = [[event allTouches] anyObject];
    CGPoint pt = [touch locationInView:_container];
    if (CGRectContainsPoint(_btnExceed.frame, pt)) {
        // Instant MAX-Act Trigger!
        if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
        SetAxisValue(4, 32767); // LT active
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SetAxisValue(4, 0);
        });
    }
}

// ---------------------------------------------------------------------------
//  Devil Bringer: Buster & Snatch Gestures
// ---------------------------------------------------------------------------

- (void)onBringerDown:(UIButton*)sender withEvent:(UIEvent*)event {
    UITouch* touch = [[event allTouches] anyObject];
    if (touch) {
        _bringerTouchStart = [touch locationInView:_container];
    }
    if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
    SetButtonBit(kB, true);
}

- (void)onBringerUp:(UIButton*)sender withEvent:(UIEvent*)event {
    UITouch* touch = [[event allTouches] anyObject];
    if (touch && _settings.combatGesturesEnabled) {
        CGPoint pt = [touch locationInView:_container];
        CGFloat dx = pt.x - _bringerTouchStart.x;
        if (dx < -30.0f) {
            // Swipe toward screen center -> Snatch! (Lock-On + Buster pulls enemy to Nero)
            SetButtonBit(kRB, true);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (_settings.lockOn != dmc4::touch::LockOnMode::Toggle || !_lockOnLatched) {
                    SetButtonBit(kRB, false);
                }
            });
        }
    }
    SetButtonBit(kB, false);
}

// ---------------------------------------------------------------------------
//  Action Event Handlers
// ---------------------------------------------------------------------------

- (void)onJumpDown {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit(kA, true);
}
- (void)onJumpUp {
    SetButtonBit(kA, false);
}

- (void)onShootDown {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastShootTapTime < 0.32) {
        // Double-tap Shoot toggles Auto-Hold Charge Shot (CS3)!
        _chargeShotLatched = !_chargeShotLatched;
        if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
        SetButtonBit(kX, _chargeShotLatched);
        [_btnShoot pulseChargingHalo:_chargeShotLatched];
        _lastShootTapTime = 0;
        return;
    }
    _lastShootTapTime = now;

    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    if (_settings.autoChargeShotLatch) {
        _chargeShotLatched = !_chargeShotLatched;
        SetButtonBit(kX, _chargeShotLatched);
        [_btnShoot pulseChargingHalo:_chargeShotLatched];
    } else {
        if (_chargeShotLatched) {
            // Tap discharges active latch
            _chargeShotLatched = NO;
            [_btnShoot pulseChargingHalo:NO];
            SetButtonBit(kX, false);
        } else {
            SetButtonBit(kX, true);
        }
    }
}
- (void)onShootUp {
    if (!_chargeShotLatched) {
        SetButtonBit(kX, false);
    }
}

- (void)onExceedDown {
    if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
    SetAxisValue(4, 32767); // Full LT trigger press
}
- (void)onExceedUp {
    SetAxisValue(4, 0);
}

- (void)onLockOnTapped {
    if (_settings.lockOn == dmc4::touch::LockOnMode::Toggle) {
        _lockOnLatched = !_lockOnLatched;
        if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
        SetButtonBit(kRB, _lockOnLatched);
        _btnLockOn.glowBorder.strokeColor = _lockOnLatched ? [UIColor colorWithRed:0.0f green:1.0f blue:0.5f alpha:1.0f].CGColor : _btnLockOn.themeColor.CGColor;
    }
}

- (void)onLockOnHoldDown {
    if (_settings.lockOn == dmc4::touch::LockOnMode::Hold) {
        if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
        SetButtonBit(kRB, true);
    }
}

- (void)onLockOnHoldUp {
    if (_settings.lockOn == dmc4::touch::LockOnMode::Hold) {
        SetButtonBit(kRB, false);
    }
}

- (void)onDTDown {
    if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
    SetButtonBit(kLB, true);
}
- (void)onDTUp {
    SetButtonBit(kLB, false);
}

- (void)onTauntDown {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit(kBack, true);
}
- (void)onTauntUp {
    SetButtonBit(kBack, false);
}

- (void)onStyleDown:(UIButton*)sender {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit((int)sender.tag, true);
}
- (void)onStyleUp:(UIButton*)sender {
    SetButtonBit((int)sender.tag, false);
}

- (void)onResetCamTapped {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit(kR3, true);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SetButtonBit(kR3, false);
    });
}

- (void)onModeChanged:(UISegmentedControl*)sender {
    switch (sender.selectedSegmentIndex) {
        case 0: // NERO: Full Action HUD, Exceed & Bringer Prominent
            _container.hidden = NO;
            _btnMelee.hidden = NO;
            _btnBringer.hidden = NO;
            _btnJump.hidden = NO;
            _btnShoot.hidden = NO;
            _btnExceed.hidden = NO;
            _btnLockOn.hidden = NO;
            _btnDevilTrigger.hidden = NO;
            _styleCrossContainer.hidden = YES;
            _stickBase.hidden = NO;
            _stickThumb.hidden = NO;
            break;
        case 1: // DANTE: Action HUD + Dante 4-Style Quick Cross
            _container.hidden = NO;
            _btnMelee.hidden = NO;
            _btnBringer.hidden = NO;
            _btnJump.hidden = NO;
            _btnShoot.hidden = NO;
            _btnExceed.hidden = NO;
            _btnLockOn.hidden = NO;
            _btnDevilTrigger.hidden = NO;
            _styleCrossContainer.hidden = NO;
            _stickBase.hidden = NO;
            _stickThumb.hidden = NO;
            break;
        case 2: // EXPLORE: Simplified walking/navigation
            _container.hidden = NO;
            _btnMelee.hidden = YES;
            _btnBringer.hidden = NO; // Keep Buster/Snatch for traversal
            _btnJump.hidden = NO;
            _btnShoot.hidden = YES;
            _btnExceed.hidden = YES;
            _btnLockOn.hidden = YES;
            _btnDevilTrigger.hidden = YES;
            _styleCrossContainer.hidden = YES;
            _stickBase.hidden = NO;
            _stickThumb.hidden = NO;
            break;
        case 3: // HIDE: Cinematic Clean Screen
            _container.hidden = YES;
            // Tap anywhere on screen restores HUD
            UITapGestureRecognizer* tapToRestore = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onRestoreHUD)];
            [self.view addGestureRecognizer:tapToRestore];
            break;
    }
}

- (void)onRestoreHUD {
    _container.hidden = NO;
    _modeSegment.selectedSegmentIndex = 0;
    [self onModeChanged:_modeSegment];
}

- (void)onGearTapped {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];

    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"DMC4 Touch & Combat Settings"
                                                                   message:@"Configure Stylish Action Touch HUD"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:(_settings.lockOn == dmc4::touch::LockOnMode::Toggle ? @"Lock-On: 1-Tap Toggle (Active)" : @"Lock-On: Hold Mode")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        _settings.lockOn = (_settings.lockOn == dmc4::touch::LockOnMode::Toggle) ? dmc4::touch::LockOnMode::Hold : dmc4::touch::LockOnMode::Toggle;
        dmc4::touch::UpdateSettings(_settings);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:(_settings.autoChargeShotLatch ? @"Auto-Hold Charge Shot (CS3): ON" : @"Auto-Hold Charge Shot (CS3): OFF")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        _settings.autoChargeShotLatch = !_settings.autoChargeShotLatch;
        dmc4::touch::UpdateSettings(_settings);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:(_settings.combatGesturesEnabled ? @"Combat Gestures (Streak/High Time/Snatch): ON" : @"Combat Gestures: OFF")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        _settings.combatGesturesEnabled = !_settings.combatGesturesEnabled;
        dmc4::touch::UpdateSettings(_settings);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:(_settings.cameraPanZoneEnabled ? @"Right-Screen Camera Pan: ON" : @"Right-Screen Camera Pan: OFF")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        _settings.cameraPanZoneEnabled = !_settings.cameraPanZoneEnabled;
        dmc4::touch::UpdateSettings(_settings);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:(_settings.danteStyleCrossVisible ? @"Dante 4-Style Cross: Visible" : @"Dante 4-Style Cross: Hidden")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        _settings.danteStyleCrossVisible = !_settings.danteStyleCrossVisible;
        dmc4::touch::UpdateSettings(_settings);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:(_settings.hapticsEnabled ? @"CoreHaptics Impact: ON" : @"CoreHaptics Impact: OFF")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        _settings.hapticsEnabled = !_settings.hapticsEnabled;
        dmc4::touch::UpdateSettings(_settings);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil]];

    alert.popoverPresentationController.sourceView = _btnGear;
    alert.popoverPresentationController.sourceRect = _btnGear.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
//  Controller Auto-Hide Integration
// ---------------------------------------------------------------------------

- (void)setupControllerNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onControllerConnected:)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onControllerDisconnected:)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
}

- (void)onControllerConnected:(NSNotification*)note {
    if (_settings.hideWhenControllerConnected && !_hudHidden) {
        REXLOG_INFO("[DMC4 Touch] Physical controller connected. Auto-hiding on-screen touch controls.");
        _container.hidden = YES;
    }
}

- (void)onControllerDisconnected:(NSNotification*)note {
    if ([GCController controllers].count == 0 && !_hudHidden) {
        REXLOG_INFO("[DMC4 Touch] Physical controller disconnected. Restoring touch controls.");
        _container.hidden = NO;
        [self bringToFront];
    }
}

@end

// ---------------------------------------------------------------------------
//  Public API Implementation
// ---------------------------------------------------------------------------

namespace dmc4::touch {

static DMC4TouchOverlayViewController* g_overlay_vc = nullptr;
static TouchSettings g_settings;

void InstallTouchOverlay(UIView* parentView) {
    if (!parentView) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_overlay_vc) {
            g_overlay_vc = [[DMC4TouchOverlayViewController alloc] init];
            g_overlay_vc.view.frame = parentView.bounds;
            [parentView addSubview:g_overlay_vc.view];
            [g_overlay_vc bringToFront];
            REXLOG_INFO("[DMC4 Touch] Installed stylish combat overlay with DMC4 procedural vector glyphs (zPosition=9999).");
        }
    });
}

void BringTouchOverlayToFront() {
    if (g_overlay_vc) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_overlay_vc bringToFront];
        });
    }
}

void UpdateSettings(const TouchSettings& settings) {
    g_settings = settings;
    if (g_overlay_vc) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_overlay_vc applySettings:settings];
        });
    }
}

TouchSettings GetCurrentSettings() {
    return g_settings;
}

void SetOverlayVisible(bool visible) {
    if (g_overlay_vc) {
        dispatch_async(dispatch_get_main_queue(), ^{
            g_overlay_vc.view.hidden = !visible;
        });
    }
}

bool IsOverlayVisible() {
    return g_overlay_vc && !g_overlay_vc.view.hidden;
}

} // namespace dmc4::touch
