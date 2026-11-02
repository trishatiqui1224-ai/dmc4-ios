# Devil May Cry 4 (iOS / iPadOS Native Static Recompilation Port)

Native ARM64 static recompilation port of **Devil May Cry 4 (Xbox 360, Title ID: `434307DF`, Capcom MT Framework — `Devil May Cry 4 (USA, Europe) (En,Fr,De,Es,It)`)** powered by ReXGlue, MoltenVK (Metal 3), and Apple Silicon hardware acceleration.

---

## Key Features & Hardened Architecture

- **True Native ARM64 Execution:** Recompiled directly from Xbox 360 PowerPC machine code to native AArch64 C++ with zero emulation JIT overhead.
- **Capcom MT Framework Optimization:**
  - Fast FBO EDRAM path (`--render_target_path_vulkan=fbo`).
  - 2D menu UI texture invalidation fix (`--clear_memory_page_state=true`, `--ios_invalidation_widen_kb=256`).
  - Zero cubemap and resolve CPU-GPU stalls (`--occlusion_query_enable=false`, `--readback_memexport=false`, `--readback_resolve=none`).
  - Preserved multi-channel audio cutscene & combat voice stability (`--ios_xma_starve_reset=false`).
  - Contrast Adaptive Sharpening (CAS) and optional MetalFX Spatial Upscaling.
- **Sandbox Filesystem Safety:**
  - Sandboxed path redirection: `$XDG_DATA_HOME` (`Documents/rex_data`), `$XDG_CACHE_HOME` (`Library/Caches`), `$XDG_CONFIG_HOME` (`Documents/config`), `$TMPDIR` (`NSTemporaryDirectory()`).
  - Thread-safe Vulkan pipeline cache disk serialization (`434307DF.fbo.*.vkcache`) via atomic write-to-temp-file and atomic rename.
- **Stateless `pread()` ISO Streaming:**
  - Chunked streaming of the ~7.3 GB ISO directly from iOS `Documents/` using POSIX stateless `pread` with thread-safe sector caching.
- **Stylish Combat Multi-Touch System:**
  - Dedicated always-on-top passthrough UIKit overlay (`layer.zPosition = 9999.0f`).
  - **Left-Thumb Movement:** Smooth 360° Analog Stick or 8-Way Directional Rocker Cluster for instant Lock-On *Back-to-Forward* command inputs (*Stinger*, *Streak*, *High Time*, *Shuffle*, *Calibur*).
  - **Right-Thumb Action Cluster:**
    - `MELEE (Y)` — Red Queen / Rebellion (oversized primary button).
    - `DEVIL BRINGER / STYLE (B)` — Buster / Snatch / Style Action.
    - `JUMP / EVADE (A)`.
    - `SHOOT (X)` — Blue Rose / Ebony & Ivory with optional **Auto-Hold Charge Shot (`CS3`) Latch** toggle.
    - `EXCEED REV (LT)` — Positioned right beside Melee for effortless thumb-slide **MAX-Act / Instant-Rev** timing on sword impact.
    - `DEVIL TRIGGER (LB)` & `TAUNT (Back)`.
  - **Smart Lock-On (`RB`):** Live switchable **1-Tap Toggle Lock-On** vs **Hold Lock-On**.
  - **Dante 4-Style Quick Cross:** Instant style switching (`T` Trickster Up, `S` Swordmaster Right, `G` Gunslinger Left, `R` Royalguard Down).
  - **CoreHaptics & Controller Support:** Crisp haptic pulse on Exceed/DT; automatic auto-hide on physical MFi/Xbox/DualSense controller connection with manual override pill.
- **Studio-Grade AppIcon:**
  - 4096x4096 procedural master featuring the "Order of the Sword / Devil Bringer" design with clashing Cyan-Violet and Crimson energy arcs, crossed Red Queen & Rebellion blades, and beveled chrome DMC centerpiece downsampled via Lanczos to strict 24-bit RGB iOS icon sizes.

---

## Directory Structure

```
dmc4-ios/
├── .github/workflows/build-ipa.yml   # macOS 15 GitHub Actions CI
├── codemagic.yaml                    # Automated Mac Mini M2 CI pipeline
├── build_ipa.sh                      # Local & CI build script
├── CMakeLists.txt                    # Root CMake specification
├── CMakePresets.json                 # iOS ARM64 native preset
├── dmc4_manifest.toml                # Authoritative 23,000+ function AOT manifest
├── requirements.txt                  # Python dependencies
├── xex/
│   └── dmc4_default.xex              # Staged DMC4 executable (3.9 MB)
├── tools/
│   ├── build_dmc4_codegen.py         # Static analysis, switch extractor & branch healer
│   ├── generate_appicon.py           # 4096px studio icon generator
│   ├── icon_preview_sheet.png        # Icon visual inspection sheet
│   ├── xex_image.py                  # Pure-Python XEX2 & PE .pdata decoder
│   └── ios/
│       ├── prepare_sdk.py            # SDK patch applicator with anchor assertions
│       └── patch_engine.py           # Atomic block patch engine
├── ios/
│   ├── CMakeLists.txt                # Application bundle and IPA packaging targets
│   ├── CMakePresets.json             # iOS build preset
│   ├── Info.plist.in                 # Application metadata with ProMotion & File Sharing
│   ├── dmc4.entitlements             # Extended virtual addressing & increased memory limit
│   ├── resources/Assets.xcassets/    # Validated AppIcon asset catalog
│   └── src/
│       ├── ios_main.mm               # Sandbox safety, signal handlers, watchdog
│       ├── launcher.mm               # Pre-launch UI & preset selector
│       ├── touch_controls.mm         # Stylish action multi-touch overlay
│       ├── audio/coreaudio_driver.mm # Low-latency RemoteIO AudioUnit
│       └── vfs/iso_piece_reader.mm   # Stateless pread() ISO streaming
└── src/
    └── dmc4_kernel_stubs.cpp         # Offline XAM/XLive sign-in & leaderboard stubs
```

---

## Sideloading & Installation Guide

### LiveContainer (Recommended)
1. Download `DMC4-iOS-unsigned.ipa` from GitHub Releases / CI artifacts.
2. Open **LiveContainer** and install `DMC4-iOS-unsigned.ipa`.
3. In LiveContainer App Settings for Devil May Cry 4:
   - Enable **JIT / CS_DEBUGGED**.
   - Enable **Increased Memory Limit** and **Extended Virtual Addressing**.
4. Transfer your game ISO or extracted folder:
   - Using the iOS **Files** app: Go to `On My iPhone` -> `LiveContainer` -> `Data` -> `App` -> `com.recomp.dmc4.ios` -> `Documents`.
   - Place `Devil May Cry 4 (USA, Europe) (En,Fr,De,Es,It).iso` (or any `*.iso`) or an extracted `game/` folder with `default.xex`.

### SideStore / AltStore / TrollStore
- Install `DMC4-iOS-unsigned.ipa` directly.
- Open the iOS **Files** app -> `On My iPhone` -> `Devil May Cry 4`.
- Place your `dmc4.iso` in the `Documents` directory.

---

## Building from Source

### Prerequisites
- macOS 14+ with Xcode 15+ installed
- CMake 3.25+ and Ninja (`brew install cmake ninja`)
- Python 3.10+ with Pillow (`pip install -r requirements.txt`)

### Build Steps
```bash
# 1. Clone repository
git clone https://github.com/your-org/dmc4-ios.git
cd dmc4-ios

# 2. Run automated build script
chmod +x build_ipa.sh
./build_ipa.sh
```

The resulting `DMC4-iOS-unsigned.ipa` will be output to `dist/`.

---

## Technical Specifications

| Parameter | Value |
|---|---|
| **Title ID** | `434307DF` |
| **Original Platform** | Xbox 360 |
| **Target Platform** | iOS 16.0+ / iPadOS 16.0+ (ARM64) |
| **Game Engine** | Capcom MT Framework 1.4 |
| **Graphics API** | Vulkan 1.3 via MoltenVK v1.4.1 (Metal 3) |
| **Audio Driver** | CoreAudio RemoteIO AudioUnit (48 kHz Stereo / 5.1) |
| **Display Support** | 60 Hz / 120 Hz ProMotion, Variable Refresh Rate |
| **VFS Architecture** | Chunked stateless `pread(fd, ...)` with sector caching |
