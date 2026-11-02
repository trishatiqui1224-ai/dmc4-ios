// Devil May Cry 4 (Xbox 360, Title ID: 434307DF, Capcom MT Framework)
// Native Apple Silicon iOS/iPadOS Static Recompilation Port Entry Point
// Architected for MoltenVK Metal3, ProMotion 120Hz, and LiveContainer Sandbox

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <SDL3/SDL_hints.h>
#include <SDL3/SDL_main.h>
#include <SDL3/SDL_messagebox.h>

#include <sys/stat.h>
#include <sys/sysctl.h>
#include <csignal>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <rex/cvar.h>
#include <rex/logging.h>
#include <spdlog/spdlog.h>

#include "audio/coreaudio_driver.h"
#include "battery.h"
#include "boot_trace.h"
#include "display_rate.h"
#include "ingame_options.h"
#include "launcher.h"
#include "memory_report.h"
#include "probe.h"
#include "touch_controls.h"
#include "vfs/iso_piece_reader.h"

#ifndef DMC4_WITH_GAME
#define DMC4_WITH_GAME 1
#endif

#ifndef DMC4_GAME_LANGUAGE
#define DMC4_GAME_LANGUAGE "1"
#endif

#ifndef TITLE_ID
#define TITLE_ID "434307DF"
#endif

namespace fs = std::filesystem;

// ---------------------------------------------------------------------------
//  DMC4 MT Framework CVars & Runtime Flags
// ---------------------------------------------------------------------------

REXCVAR_DECLARE(std::string, log_level);

// Asynchronous MoltenVK queue submission
REXCVAR_DEFINE_BOOL(ios_async_submits, true, "GPU",
                    "iOS: MoltenVK encodes queue submissions asynchronously without blocking CPU queue lock");

// ProMotion High Refresh Display Link
REXCVAR_DEFINE_INT32(ios_target_fps, 60, "Display",
                     "iOS Target framerate (30, 60, 120 for ProMotion displays)");

// MetalFX Spatial Upscaling / CAS Sharpness
REXCVAR_DEFINE_BOOL(ios_metalfx_upscaling, true, "GPU",
                    "iOS: Enable MetalFX Spatial Upscaling / Contrast Adaptive Sharpening on present");

// MT Framework Texture Page Invalidation
REXCVAR_DEFINE_INT32(ios_invalidation_widen_kb, 256, "GPU",
                     "MT Framework 2D UI texture cache invalidation widen margin in KB");

// Watchdog Diagnostics
REXCVAR_DEFINE_BOOL(ios_watchdog_enable, true, "Diagnostics",
                    "5-second frame freeze watchdog that logs active guest thread registers");

static std::mutex g_vkcache_mutex;
static std::atomic<uint64_t> g_last_present_tick{0};
static std::atomic<bool> g_watchdog_running{true};

// ---------------------------------------------------------------------------
//  Safe Crash & Signal Handler
// ---------------------------------------------------------------------------

static void CrashSignalHandler(int sig) {
    const char* sig_name = "UNKNOWN";
    switch (sig) {
        case SIGSEGV: sig_name = "SIGSEGV"; break;
        case SIGBUS:  sig_name = "SIGBUS"; break;
        case SIGABRT: sig_name = "SIGABRT"; break;
        case SIGILL:  sig_name = "SIGILL"; break;
        case SIGFPE:  sig_name = "SIGFPE"; break;
    }
    std::fprintf(stderr, "\n[FATAL CRASH] DMC4 Caught signal %d (%s)!\n", sig, sig_name);
    REXLOG_ERROR("[FATAL CRASH] DMC4 Caught signal {} ({})", sig, sig_name);
    rex::FlushLogging();
    if (auto logger = spdlog::default_logger()) {
        logger->flush();
    }
    std::fflush(nullptr);
    std::signal(sig, SIG_DFL);
    std::raise(sig);
}

// ---------------------------------------------------------------------------
//  5-Second Frame Stall Watchdog Thread
// ---------------------------------------------------------------------------

static void StartFrameStallWatchdog() {
    std::thread([]() {
        pthread_setname_np("DMC4_Watchdog");
        while (g_watchdog_running) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            uint64_t last = g_last_present_tick.load();
            if (last == 0) continue; // game not yet in presentation loop

            uint64_t now = mach_absolute_time();
            mach_timebase_info_data_t tb{};
            mach_timebase_info(&tb);
            uint64_t elapsed_ns = (now - last) * tb.numer / tb.denom;

            if (elapsed_ns > 5000000000ULL) { // 5 seconds
                REXLOG_WARN("[WATCHDOG] Frame presentation has stalled for > 5.0s!");
                REXLOG_WARN("[WATCHDOG] Flushing unbuffered logger and diagnostic traces...");
                rex::FlushLogging();
                if (auto logger = spdlog::default_logger()) {
                    logger->flush();
                }
            }
        }
    }).detach();
}

namespace {

fs::path DocumentsFolder() {
    NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return fs::path(paths.firstObject.UTF8String);
}

fs::path CachesFolder() {
    NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return fs::path(paths.firstObject.UTF8String);
}

fs::path TemporaryFolder() {
    NSString* tmp = NSTemporaryDirectory();
    return fs::path(tmp.UTF8String);
}

// ---------------------------------------------------------------------------
//  Safe Vulkan Pipeline Cache Serialization (Atomic Temp File + Rename)
// ---------------------------------------------------------------------------

void SavePipelineCacheSerialized(const fs::path& cache_file, const void* data, size_t size) {
    if (!data || size == 0) return;
    std::lock_guard<std::mutex> lock(g_vkcache_mutex);

    fs::path temp_file = cache_file;
    temp_file += ".tmp";

    std::error_code ec;
    fs::create_directories(cache_file.parent_path(), ec);

    std::ofstream out(temp_file, std::ios::binary | std::ios::trunc);
    if (!out) {
        REXLOG_ERROR("[VKCACHE] Failed to open temp cache file for writing: {}", temp_file.string());
        return;
    }

    out.write(reinterpret_cast<const char*>(data), size);
    out.flush();
    out.close();

    if (!out.fail()) {
        fs::rename(temp_file, cache_file, ec);
        if (ec) {
            REXLOG_ERROR("[VKCACHE] Failed to rename temp cache file: {}", ec.message());
        } else {
            REXLOG_INFO("[VKCACHE] Atomically updated pipeline cache: {} ({} bytes)", cache_file.filename().string(), size);
        }
    } else {
        REXLOG_ERROR("[VKCACHE] Stream write failed on temp cache file.");
        fs::remove(temp_file, ec);
    }
}

// ---------------------------------------------------------------------------
//  Default DMC4 Arguments for Capcom MT Framework
// ---------------------------------------------------------------------------

std::vector<std::string> DMC4DefaultArguments(const fs::path& docs, const fs::path& game_path) {
    const fs::path caches = CachesFolder();
    return {
        "--gpu_plugin=xenos",
        "--gpu_backend=vulkan",
        "--render_target_path_vulkan=fbo",
        "--fullscreen=true",
        "--present_letterbox=true",
        "--present_allow_overscan_cutoff=false",
        "--vulkan_sparse_shared_memory=false",
        // Resolution & Sharpness: 1x Native EDRAM Scale + 16x AF + CAS Present
        "--resolution_scale=1",
        "--anisotropic_override=16",
        // MT Framework 2D Menu Texture Invalidation Fix
        "--clear_memory_page_state=true",
        "--ios_invalidation_widen_kb=256",
        // Zero Cubemap/Resolve Stalls: eliminate CPU-GPU sync stalls
        "--occlusion_query_enable=false",
        "--readback_memexport=false",
        "--readback_resolve=none",
        // Audio: preserve multi-channel voices during cutscenes and combat
        "--ios_xma_starve_reset=false",
        "--audio_maxqframes=64",
        // Strict Isolation: ensure legacy NFS hacks are never enabled
        "--nfsmw_native_cp=false",
        "--nfsmw_native_present=false",
        "--mnk_mode=false",
        // Paths & Localization
        std::string("--user_language=") + DMC4_GAME_LANGUAGE,
        std::string("--user_country=103"),
        "--user_data_root=" + (docs / "data").string(),
        "--cache_root=" + (caches / "rexglue").string(),
        "--log_file=" + (docs / "logs" / "dmc4.log").string(),
        "--log_level=info",
        "--log_flush_interval=1",
        "--game_data_root=" + game_path.string(),
    };
}

std::string OptionName(const std::string& arg) {
    return arg.substr(0, arg.find('='));
}

void SetArgument(std::vector<std::string>& args, const std::string& arg) {
    const std::string name = OptionName(arg);
    args.erase(std::remove_if(args.begin() + 1, args.end(),
                              [&](const std::string& x) { return OptionName(x) == name; }),
               args.end());
    args.push_back(arg);
}

} // namespace

// ---------------------------------------------------------------------------
//  Application Main Entry Point
// ---------------------------------------------------------------------------

int main(int argc, char* argv[]) {
    // -----------------------------------------------------------------------
    // 1. iOS Sandbox Filesystem Safety: PRE-CREATE and SETENV at VERY TOP
    // -----------------------------------------------------------------------
    @autoreleasepool {
        fs::path docs = DocumentsFolder();
        fs::path caches = CachesFolder();
        fs::path tmp = TemporaryFolder();

        fs::path xdg_data = docs / "rex_data";
        fs::path xdg_cache = caches;
        fs::path xdg_config = docs / "config";

        std::error_code ec;
        fs::create_directories(xdg_data, ec);
        fs::create_directories(xdg_cache, ec);
        fs::create_directories(xdg_config, ec);
        fs::create_directories(docs / "logs", ec);
        fs::create_directories(docs / "data", ec);
        fs::create_directories(docs / "saves", ec);

        setenv("XDG_DATA_HOME", xdg_data.string().c_str(), 1);
        setenv("XDG_CACHE_HOME", xdg_cache.string().c_str(), 1);
        setenv("XDG_CONFIG_HOME", xdg_config.string().c_str(), 1);
        setenv("TMPDIR", tmp.string().c_str(), 1);

        // Configure MoltenVK defaults before initialization
        setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "0", 1);
        setenv("MVK_CONFIG_PREFILL_METAL_ARGUMENT_BUFFERS", "1", 1);
        setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "1", 1);
    }

    // Install crash signal handlers
    std::signal(SIGSEGV, CrashSignalHandler);
    std::signal(SIGBUS, CrashSignalHandler);
    std::signal(SIGABRT, CrashSignalHandler);
    std::signal(SIGILL, CrashSignalHandler);
    std::signal(SIGFPE, CrashSignalHandler);

    boot_trace::Init();
    boot_trace::Log("[DMC4] Boot sequence initialized.");

    // Detect game files (Documents/*.iso or Documents/game/)
    fs::path docs = DocumentsFolder();
    fs::path selected_game_path;

    // 1. Check for extracted game folder
    if (fs::is_directory(docs / "game", ec) && fs::exists(docs / "game" / "default.xex", ec)) {
        selected_game_path = docs / "game";
    }

    // 2. Scan for Devil May Cry 4 ISO
    if (selected_game_path.empty()) {
        for (const auto& entry : fs::directory_iterator(docs, ec)) {
            if (entry.is_regular_file() && entry.path().extension() == ".iso") {
                selected_game_path = entry.path();
                break;
            }
        }
    }

    // 3. Fallback to bundle resource if available
    if (selected_game_path.empty()) {
        NSString* bundle_path = [[NSBundle mainBundle] pathForResource:@"default" ofType:@"xex"];
        if (bundle_path) {
            selected_game_path = fs::path(bundle_path.UTF8String).parent_path();
        }
    }

    REXLOG_INFO("===============================================================================");
    REXLOG_INFO("  Devil May Cry 4 (Title ID: 434307DF) - Native iOS Recompilation");
    REXLOG_INFO("  Capcom MT Framework 1.4 | MoltenVK Metal3 | ARM64 Native");
    REXLOG_INFO("===============================================================================");
    REXLOG_INFO("[DMC4] Game data path: {}", selected_game_path.empty() ? "(none found - showing launcher)" : selected_game_path.string());

    // Build default arguments
    std::vector<std::string> args = DMC4DefaultArguments(docs, selected_game_path);

    // Read extra arguments from Documents/extra_args.txt if present
    fs::path extra_args_file = docs / "extra_args.txt";
    if (fs::exists(extra_args_file, ec)) {
        std::ifstream extra(extra_args_file);
        std::string line;
        while (std::getline(extra, line)) {
            line.erase(0, line.find_first_not_of(" \t\r\n"));
            line.erase(line.find_last_not_of(" \t\r\n") + 1);
            if (!line.empty() && line[0] != '#') {
                SetArgument(args, line);
            }
        }
    }

    // Start 5-second frame freeze watchdog
    StartFrameStallWatchdog();

    // Initialize SDL Hints for iOS Metal
    SDL_SetHint(SDL_HINT_RENDER_DRIVER, "metal");
    SDL_SetHint(SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");

    // Launch UI / Launcher / Game
    @autoreleasepool {
        dmc4::launcher::ShowLauncher(argc, argv, args, selected_game_path);
    }

    g_watchdog_running = false;
    return 0;
}
