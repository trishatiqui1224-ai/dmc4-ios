// Devil May Cry 4 (Title ID: 434307DF) - Stylish Action Touch Controls
// High-APM Multi-Touch UIKit Overlay with Nero/Dante Layout & Live Gear Settings

#import <GameController/GameController.h>
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

constexpr int kAxes = 6; // LX, LY, RX, RY, LT, RT

SDL_Joystick* g_virtual_pad = nullptr;
int g_active_buttons = 0;
Sint16 g_axes[kAxes] = {0};

void SyncVirtualPadState() {
    if (!g_virtual_pad) return;
    // Update buttons
    for (int i = 0; i < 15; ++i) {
        bool pressed = (g_active_buttons & (1 << i)) != 0;
        SDL_SetJoystickVirtualButton(g_virtual_pad, i, pressed ? 1 : 0);
    }
    // Update axes (LX, LY, RX, RY, LT, RT)
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
//  Always-On-Top Passthrough Container View
// ---------------------------------------------------------------------------

@interface TouchOverlayContainerView : UIView
@property (nonatomic, assign) BOOL allowPassthrough;
@end

@implementation TouchOverlayContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.zPosition = 9999.0f; // Always strictly on top of CAMetalLayer / MoltenVK
        self.multipleTouchEnabled = YES;
        self.userInteractionEnabled = YES;
        self.allowPassthrough = YES;
    }
    return self;
}

- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* hit = [super hitTest:point withEvent:event];
    if (hit == self && self.allowPassthrough) {
        // Touches on empty space pass straight through to game presentation
        return nil;
    }
    return hit;
}

@end

// ---------------------------------------------------------------------------
//  DMC4 Combat HUD Overlay Controller
// ---------------------------------------------------------------------------

@interface DMC4TouchOverlayViewController : UIViewController {
    TouchOverlayContainerView* _container;
    dmc4::touch::TouchSettings _settings;

    // Left Thumb Controls
    UIView* _stickBase;
    UIView* _stickThumb;
    CGPoint _stickCenter;
    BOOL _stickActive;
    UIView* _dpadView;

    // Combat Action Cluster (Right Thumb)
    UIButton* _btnMelee;       // Y - Oversized
    UIButton* _btnBringer;     // B - Devil Bringer / Buster
    UIButton* _btnJump;        // A - Jump
    UIButton* _btnShoot;       // X - Shoot
    UIButton* _btnExceed;      // LT - Instant Rev / MAX-Act
    UIButton* _btnLockOn;      // RB - Smart Lock-On
    UIButton* _btnDevilTrigger;// LB - Devil Trigger
    UIButton* _btnTaunt;       // Back - Taunt

    // Dante 4-Style Quick Cross
    UIView* _styleCrossView;
    UIButton* _btnTrickster;   // Up
    UIButton* _btnSwordmaster; // Right
    UIButton* _btnGunslinger;  // Left
    UIButton* _btnRoyalguard;  // Down

    // Top Bar Pill & Tools
    UIView* _topBarPill;
    UILabel* _fpsLabel;
    UIButton* _btnGear;
    UIButton* _btnPause;
    UIButton* _btnResetCamera; // RS

    // State
    BOOL _lockOnLatched;
    BOOL _chargeShotLatched;
    BOOL _manualHidden;

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
    [self setupControllerNotifications];
    [self updateLayout];
}

- (void)setupControls {
    // 1. Left Thumb Analog Stick
    _stickBase = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 160, 160)];
    _stickBase.backgroundColor = [UIColor colorWithWhite:0.15f alpha:0.45f];
    _stickBase.layer.cornerRadius = 80.0f;
    _stickBase.layer.borderColor = [UIColor colorWithRed:0.0f green:0.85f blue:1.0f alpha:0.5f].CGColor;
    _stickBase.layer.borderWidth = 2.0f;
    _stickBase.userInteractionEnabled = NO;
    [_container addSubview:_stickBase];

    _stickThumb = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 70, 70)];
    _stickThumb.backgroundColor = [UIColor colorWithRed:0.0f green:0.75f blue:0.95f alpha:0.75f];
    _stickThumb.layer.cornerRadius = 35.0f;
    _stickThumb.layer.borderColor = [UIColor whiteColor].CGColor;
    _stickThumb.layer.borderWidth = 1.5f;
    _stickThumb.userInteractionEnabled = NO;
    [_container addSubview:_stickThumb];

    // 2. Right Thumb Stylish Action Buttons
    _btnMelee = [self createCombatButton:@"MELEE\n(Y)" color:[UIColor colorWithRed:0.95f green:0.15f blue:0.25f alpha:0.85f] size:92.0f];
    [_btnMelee addTarget:self action:@selector(onMeleeDown) forControlEvents:UIControlEventTouchDown];
    [_btnMelee addTarget:self action:@selector(onMeleeUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    _btnBringer = [self createCombatButton:@"BRINGER\n(B)" color:[UIColor colorWithRed:0.0f green:0.88f blue:1.0f alpha:0.85f] size:78.0f];
    [_btnBringer addTarget:self action:@selector(onBringerDown) forControlEvents:UIControlEventTouchDown];
    [_btnBringer addTarget:self action:@selector(onBringerUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    _btnJump = [self createCombatButton:@"JUMP\n(A)" color:[UIColor colorWithRed:0.2f green:0.85f blue:0.35f alpha:0.85f] size:78.0f];
    [_btnJump addTarget:self action:@selector(onJumpDown) forControlEvents:UIControlEventTouchDown];
    [_btnJump addTarget:self action:@selector(onJumpUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    _btnShoot = [self createCombatButton:@"SHOOT\n(X)" color:[UIColor colorWithRed:0.2f green:0.5f blue:1.0f alpha:0.85f] size:78.0f];
    [_btnShoot addTarget:self action:@selector(onShootDown) forControlEvents:UIControlEventTouchDown];
    [_btnShoot addTarget:self action:@selector(onShootUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    // Exceed Rev (LT) - Positioned right beside Melee for instant MAX-Act / Instant-Rev!
    _btnExceed = [self createCombatButton:@"EXCEED\nREV (LT)" color:[UIColor colorWithRed:1.0f green:0.45f blue:0.0f alpha:0.9f] size:84.0f];
    _btnExceed.layer.borderColor = [UIColor colorWithRed:1.0f green:0.8f blue:0.0f alpha:0.9f].CGColor;
    _btnExceed.layer.borderWidth = 2.5f;
    [_btnExceed addTarget:self action:@selector(onExceedDown) forControlEvents:UIControlEventTouchDown];
    [_btnExceed addTarget:self action:@selector(onExceedUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    // Smart Lock-On (RB)
    _btnLockOn = [self createCombatButton:@"LOCK-ON\n(RB)" color:[UIColor colorWithRed:0.7f green:0.2f blue:0.9f alpha:0.85f] size:74.0f];
    [_btnLockOn addTarget:self action:@selector(onLockOnTapped) forControlEvents:UIControlEventTouchUpInside];
    [_btnLockOn addTarget:self action:@selector(onLockOnHoldDown) forControlEvents:UIControlEventTouchDown];
    [_btnLockOn addTarget:self action:@selector(onLockOnHoldUp) forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    // Devil Trigger (LB) & Taunt (Back)
    _btnDevilTrigger = [self createCombatButton:@"DT (LB)" color:[UIColor colorWithRed:0.9f green:0.1f blue:0.3f alpha:0.8f] size:64.0f];
    [_btnDevilTrigger addTarget:self action:@selector(onDTDown) forControlEvents:UIControlEventTouchDown];
    [_btnDevilTrigger addTarget:self action:@selector(onDTUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    _btnTaunt = [self createCombatButton:@"TAUNT" color:[UIColor colorWithWhite:0.25f alpha:0.8f] size:58.0f];
    [_btnTaunt addTarget:self action:@selector(onTauntDown) forControlEvents:UIControlEventTouchDown];
    [_btnTaunt addTarget:self action:@selector(onTauntUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    // 3. Dante 4-Style Quick Cross
    _styleCrossView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 140, 140)];
    _styleCrossView.backgroundColor = [UIColor colorWithWhite:0.12f alpha:0.5f];
    _styleCrossView.layer.cornerRadius = 70.0f;
    _styleCrossView.layer.borderColor = [UIColor colorWithRed:1.0f green:0.2f blue:0.2f alpha:0.5f].CGColor;
    _styleCrossView.layer.borderWidth = 1.5f;
    [_container addSubview:_styleCrossView];

    _btnTrickster = [self createStyleButton:@"T\nTrickster" color:[UIColor colorWithRed:0.9f green:0.75f blue:0.1f alpha:0.9f] direction:kUp];
    _btnSwordmaster = [self createStyleButton:@"S\nSwordmaster" color:[UIColor colorWithRed:0.95f green:0.15f blue:0.2f alpha:0.9f] direction:kRight];
    _btnGunslinger = [self createStyleButton:@"G\nGunslinger" color:[UIColor colorWithRed:0.1f green:0.7f blue:0.95f alpha:0.9f] direction:kLeft];
    _btnRoyalguard = [self createStyleButton:@"R\nRoyalguard" color:[UIColor colorWithRed:0.3f green:0.2f blue:0.85f alpha:0.9f] direction:kDown];

    [_styleCrossView addSubview:_btnTrickster];
    [_styleCrossView addSubview:_btnSwordmaster];
    [_styleCrossView addSubview:_btnGunslinger];
    [_styleCrossView addSubview:_btnRoyalguard];

    // 4. Top Bar Controls
    _topBarPill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 38)];
    _topBarPill.backgroundColor = [UIColor colorWithWhite:0.1f alpha:0.75f];
    _topBarPill.layer.cornerRadius = 19.0f;
    _topBarPill.layer.borderColor = [UIColor colorWithWhite:0.4f alpha:0.6f].CGColor;
    _topBarPill.layer.borderWidth = 1.0f;
    [_container addSubview:_topBarPill];

    _fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 4, 75, 30)];
    _fpsLabel.text = @"60 FPS";
    _fpsLabel.textColor = [UIColor colorWithRed:0.2f green:1.0f blue:0.4f alpha:1.0f];
    _fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0f weight:UIFontWeightBold];
    [_topBarPill addSubview:_fpsLabel];

    _btnPause = [UIButton buttonWithType:UIButtonTypeSystem];
    _btnPause.frame = CGRectMake(95, 4, 65, 30);
    [_btnPause setTitle:@"PAUSE" forState:UIControlStateNormal];
    [_btnPause setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnPause.titleLabel.font = [UIFont systemFontOfSize:12.0f weight:UIFontWeightSemibold];
    [_btnPause addTarget:self action:@selector(onPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topBarPill addSubview:_btnPause];

    _btnResetCamera = [UIButton buttonWithType:UIButtonTypeSystem];
    _btnResetCamera.frame = CGRectMake(165, 4, 75, 30);
    [_btnResetCamera setTitle:@"CAM (RS)" forState:UIControlStateNormal];
    [_btnResetCamera setTitleColor:[UIColor colorWithRed:0.8f green:0.9f blue:1.0f alpha:1.0f] forState:UIControlStateNormal];
    _btnResetCamera.titleLabel.font = [UIFont systemFontOfSize:11.0f weight:UIFontWeightMedium];
    [_btnResetCamera addTarget:self action:@selector(onResetCamTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topBarPill addSubview:_btnResetCamera];

    _btnGear = [UIButton buttonWithType:UIButtonTypeSystem];
    _btnGear.frame = CGRectMake(245, 4, 65, 30);
    [_btnGear setTitle:@"GEAR ⚙" forState:UIControlStateNormal];
    [_btnGear setTitleColor:[UIColor colorWithRed:1.0f green:0.85f blue:0.2f alpha:1.0f] forState:UIControlStateNormal];
    _btnGear.titleLabel.font = [UIFont systemFontOfSize:12.0f weight:UIFontWeightBold];
    [_btnGear addTarget:self action:@selector(onGearTapped) forControlEvents:UIControlEventTouchUpInside];
    [_topBarPill addSubview:_btnGear];
}

- (UIButton*)createCombatButton:(NSString*)title color:(UIColor*)color size:(CGFloat)size {
    UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, size, size);
    btn.backgroundColor = color;
    btn.layer.cornerRadius = size / 2.0f;
    btn.layer.borderColor = [UIColor whiteColor].CGColor;
    btn.layer.borderWidth = 1.5f;
    btn.titleLabel.numberOfLines = 2;
    btn.titleLabel.textAlignment = NSTextAlignmentCenter;
    btn.titleLabel.font = [UIFont systemFontOfSize:11.5f weight:UIFontWeightBold];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    btn.layer.shadowOpacity = 0.5f;
    btn.layer.shadowRadius = 4.0f;
    [_container addSubview:btn];
    return btn;
}

- (UIButton*)createStyleButton:(NSString*)title color:(UIColor*)color direction:(int)bitmask {
    UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, 42, 42);
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 21.0f;
    btn.layer.borderColor = [UIColor whiteColor].CGColor;
    btn.layer.borderWidth = 1.0f;
    btn.titleLabel.numberOfLines = 2;
    btn.titleLabel.textAlignment = NSTextAlignmentCenter;
    btn.titleLabel.font = [UIFont systemFontOfSize:9.0f weight:UIFontWeightHeavy];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.tag = bitmask;
    [btn addTarget:self action:@selector(onStyleDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(onStyleUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return btn;
}

- (void)updateLayout {
    CGSize sz = self.view.bounds.size;
    CGFloat scale = _settings.buttonScale;
    CGFloat pad = 30.0f;

    // Left Thumb Stick Center
    _stickCenter = CGPointMake(pad + 80.0f, sz.height - pad - 80.0f);
    _stickBase.center = _stickCenter;
    _stickThumb.center = _stickCenter;

    // Dante Style Cross (Left side, slightly above stick)
    _styleCrossView.center = CGPointMake(pad + 80.0f, sz.height - pad - 230.0f);
    _btnTrickster.center = CGPointMake(70, 26);
    _btnSwordmaster.center = CGPointMake(114, 70);
    _btnGunslinger.center = CGPointMake(26, 70);
    _btnRoyalguard.center = CGPointMake(70, 114);

    // Right Thumb Action Diamond + Arc
    CGFloat rightX = sz.width - pad - 90.0f;
    CGFloat rightY = sz.height - pad - 90.0f;

    _btnMelee.center = CGPointMake(rightX - 25.0f * scale, rightY - 60.0f * scale);
    _btnBringer.center = CGPointMake(rightX + 45.0f * scale, rightY - 15.0f * scale);
    _btnJump.center = CGPointMake(rightX - 25.0f * scale, rightY + 30.0f * scale);
    _btnShoot.center = CGPointMake(rightX - 95.0f * scale, rightY - 15.0f * scale);

    // Exceed Rev (LT) right above Melee (Y)
    _btnExceed.center = CGPointMake(rightX - 25.0f * scale, rightY - 155.0f * scale);

    // Smart Lock-On (RB) above Bringer (B)
    _btnLockOn.center = CGPointMake(rightX + 55.0f * scale, rightY - 105.0f * scale);

    // Devil Trigger (LB) and Taunt
    _btnDevilTrigger.center = CGPointMake(rightX - 105.0f * scale, rightY - 105.0f * scale);
    _btnTaunt.center = CGPointMake(rightX - 175.0f * scale, rightY - 35.0f * scale);

    // Top Bar Pill
    _topBarPill.center = CGPointMake(sz.width / 2.0f, 30.0f);

    _container.alpha = _settings.opacity;
    _styleCrossView.hidden = !_settings.danteStyleCrossVisible;
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
//  Touch Events: Smooth 360 Analog Stick
// ---------------------------------------------------------------------------

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    for (UITouch* t in touches) {
        CGPoint pt = [t locationInView:_container];
        if (pt.x < self.view.bounds.size.width * 0.45f && pt.y > 100.0f) {
            _stickActive = YES;
            _stickBase.center = pt;
            _stickThumb.center = pt;
            _stickCenter = pt;
            break;
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    if (!_stickActive) return;
    for (UITouch* t in touches) {
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

        // Normalize to Sint16 axes
        Sint16 axisX = static_cast<Sint16>((dx / maxR) * 32767.0f);
        Sint16 axisY = static_cast<Sint16>((dy / maxR) * 32767.0f);
        SetAxisValue(0, axisX);
        SetAxisValue(1, axisY);
        break;
    }
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    _stickActive = NO;
    _stickThumb.center = _stickCenter;
    SetAxisValue(0, 0);
    SetAxisValue(1, 0);
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    [self touchesEnded:touches withEvent:event];
}

// ---------------------------------------------------------------------------
//  Action Handlers
// ---------------------------------------------------------------------------

- (void)onMeleeDown {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit(kY, true);
}
- (void)onMeleeUp {
    SetButtonBit(kY, false);
}

- (void)onBringerDown {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit(kB, true);
}
- (void)onBringerUp {
    SetButtonBit(kB, false);
}

- (void)onJumpDown {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit(kA, true);
}
- (void)onJumpUp {
    SetButtonBit(kA, false);
}

- (void)onShootDown {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    if (_settings.autoChargeShotLatch) {
        // Double-tap or toggle auto-hold CS3
        _chargeShotLatched = !_chargeShotLatched;
        SetButtonBit(kX, _chargeShotLatched);
        _btnShoot.layer.borderColor = _chargeShotLatched ? [UIColor colorWithRed:1.0f green:0.9f blue:0.0f alpha:1.0f].CGColor : [UIColor whiteColor].CGColor;
    } else {
        SetButtonBit(kX, true);
    }
}
- (void)onShootUp {
    if (!_settings.autoChargeShotLatch) {
        SetButtonBit(kX, false);
    }
}

- (void)onExceedDown {
    // Crisp rigid pulse for Exceed Rev / MAX-Act
    if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
    // Map Exceed to Left Trigger (LT)
    SetAxisValue(4, 32767);
}
- (void)onExceedUp {
    SetAxisValue(4, 0);
}

- (void)onLockOnTapped {
    if (_settings.lockOn == dmc4::touch::LockOnMode::Toggle) {
        _lockOnLatched = !_lockOnLatched;
        if (_settings.hapticsEnabled) [_rigidHaptic impactOccurred];
        SetButtonBit(kRB, _lockOnLatched);
        _btnLockOn.layer.borderColor = _lockOnLatched ? [UIColor colorWithRed:0.0f green:1.0f blue:0.5f alpha:1.0f].CGColor : [UIColor whiteColor].CGColor;
        _btnLockOn.backgroundColor = _lockOnLatched ? [UIColor colorWithRed:0.4f green:0.1f blue:0.7f alpha:0.95f] : [UIColor colorWithRed:0.7f green:0.2f blue:0.9f alpha:0.85f];
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

- (void)onPauseTapped {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit(kStart, true);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SetButtonBit(kStart, false);
    });
}

- (void)onResetCamTapped {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    SetButtonBit(kR3, true);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SetButtonBit(kR3, false);
    });
}

- (void)onGearTapped {
    if (_settings.hapticsEnabled) [_lightHaptic impactOccurred];
    // Opens live settings dialog
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"DMC4 Touch & Combat Settings"
                                                                   message:@"Configure Stylish-Action Touch Overlay"
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

    [alert addAction:[UIAlertAction actionWithTitle:(_settings.danteStyleCrossVisible ? @"Dante 4-Style Cross: Visible" : @"Dante 4-Style Cross: Hidden")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        _settings.danteStyleCrossVisible = !_settings.danteStyleCrossVisible;
        dmc4::touch::UpdateSettings(_settings);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:(_settings.hapticsEnabled ? @"CoreHaptics: ON" : @"CoreHaptics: OFF")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        _settings.hapticsEnabled = !_settings.hapticsEnabled;
        dmc4::touch::UpdateSettings(_settings);
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Toggle Overlay (Hide/Show)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        _manualHidden = !_manualHidden;
        _container.hidden = _manualHidden;
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil]];

    alert.popoverPresentationController.sourceView = _btnGear;
    alert.popoverPresentationController.sourceRect = _btnGear.bounds;
    [self presentViewController:alert animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
//  Physical Controller Auto-Hide Integration
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
    if (_settings.hideWhenControllerConnected && !_manualHidden) {
        REXLOG_INFO("[DMC4 Touch] Physical controller connected. Auto-hiding on-screen touch controls.");
        _container.hidden = YES;
    }
}

- (void)onControllerDisconnected:(NSNotification*)note {
    if ([GCController controllers].count == 0 && !_manualHidden) {
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
            REXLOG_INFO("[DMC4 Touch] Installed always-on-top stylish combat overlay (zPosition=9999).");
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
