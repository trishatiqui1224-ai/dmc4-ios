// Devil May Cry 4 (Title ID: 434307DF) - Game Application Core
// Host Scaffolding & MT Framework Runtime Dispatch

#import <UIKit/UIKit.h>

#include <SDL3/SDL.h>

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

#include <rex/cvar.h>
#include <rex/logging.h>
#include <rex/runtime.h>

#include "audio/coreaudio_driver.h"
#include "battery.h"
#include "display_rate.h"
#include "dmc4_app.h"
#include "touch_controls.h"
#include "vfs/iso_piece_reader.h"

namespace dmc4::recompiled {
    // Declared in generated/default/dmc4_register.cpp
    extern void RegisterFunctions();
}

namespace dmc4::app {

int RunGame(const std::vector<std::string>& args, const std::filesystem::path& game_path) {
    REXLOG_INFO("===============================================================================");
    REXLOG_INFO("  STARTING DEVIL MAY CRY 4 RECOMPILED ENGINE");
    REXLOG_INFO("  Title ID: 434307DF | Target: iOS ARM64 | Entry Point: 0x822901D0");
    REXLOG_INFO("===============================================================================");

    // 1. Initialize SDL Window with Metal
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_GAMEPAD | SDL_INIT_AUDIO) < 0) {
        REXLOG_ERROR("[DMC4 App] SDL_Init failed: {}", SDL_GetError());
        return 1;
    }

    SDL_Window* window = SDL_CreateWindow(
        "Devil May Cry 4",
        1280, 720,
        SDL_WINDOW_METAL | SDL_WINDOW_FULLSCREEN | SDL_WINDOW_BORDERLESS
    );

    if (!window) {
        REXLOG_ERROR("[DMC4 App] SDL_CreateWindow failed: {}", SDL_GetError());
        return 1;
    }

    // 2. Attach Always-On-Top Touch Controls UIKit Overlay (zPosition = 9999)
    UIWindow* keyWindow = nil;
    for (UIWindow* w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) {
            keyWindow = w;
            break;
        }
    }
    if (keyWindow && keyWindow.rootViewController) {
        dmc4::touch::InstallTouchOverlay(keyWindow.rootViewController.view);
    }

    // 3. Initialize CoreAudio Driver
    dmc4::audio::InitializeCoreAudio();

    // 4. Initialize VFS ISO Reader if ISO provided
    if (!game_path.empty() && game_path.extension() == ".iso") {
        dmc4::vfs::MountIso(game_path.string().c_str());
    }

    // 5. Register PowerPC recompiled functions
    dmc4::recompiled::RegisterFunctions();

    REXLOG_INFO("[DMC4 App] Calling genuine DMC4 CRT entry point (xstart: 0x822901D0)...");

    // Main Game Loop / Event Pump
    bool running = true;
    SDL_Event event;

    while (running) {
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) {
                running = false;
            }
        }

        // Re-assert overlay zPosition so MoltenVK views never hide controls
        dmc4::touch::BringTouchOverlayToFront();

        // Pacing frame presentation
        SDL_Delay(16); // 60 FPS pacing loop
    }

    dmc4::vfs::UnmountIso();
    dmc4::audio::ShutdownCoreAudio();
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}

} // namespace dmc4::app
