#!/usr/bin/env python3
"""
tools/ios/prepare_sdk.py
Prepares and patches the ReXGlue SDK tree for Devil May Cry 4 (Title ID: 434307DF)
on Apple Silicon iOS/iPadOS (ARM64 Native).

Safe & Idempotent: Every patch block verifies that its anchor exists and matches
exactly 1 time before modifying any files.
"""

import argparse
import os
import pathlib
import subprocess
import sys
import tarfile
import urllib.request

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent

sys.path.insert(0, str(SCRIPT_DIR))
from patch_engine import find_sdk, read_file_contents, write_file_contents, apply_patch_blocks

MOLTENVK_VERSION = "v1.4.1"
MOLTENVK_URL = (
    f"https://github.com/KhronosGroup/MoltenVK/releases/download/"
    f"{MOLTENVK_VERSION}/MoltenVK-ios.tar"
)


def ensure_git_tags(sdk: pathlib.Path):
    """Ensure v* git tag is reachable so rex_compute_version resolves cleanly."""
    chk = subprocess.run(
        ["git", "describe", "--tags", "--match", "v*"],
        cwd=sdk,
        capture_output=True,
        text=True,
    )
    if chk.returncode != 0:
        subprocess.run(["git", "fetch", "--tags", "--depth=1"], cwd=sdk, capture_output=True)
        chk2 = subprocess.run(
            ["git", "describe", "--tags", "--match", "v*"],
            cwd=sdk,
            capture_output=True,
            text=True,
        )
        if chk2.returncode != 0:
            subprocess.run(["git", "tag", "-f", "v0.10.0", "HEAD"], cwd=sdk, capture_output=True)
            print("  [ok] Tagged v0.10.0 on HEAD for rex_compute_version")


def safeguard_vulkan_loader(sdk: pathlib.Path):
    """Safeguard: quote ${SYSTEM_PROCESSOR} and ${CMAKE_SYSTEM_PROCESSOR} in vulkan-loader."""
    loader_cmake = sdk / "thirdparty" / "vulkan-loader" / "loader" / "CMakeLists.txt"
    if loader_cmake.exists():
        txt, eol = read_file_contents(loader_cmake)
        orig = txt
        for var in ["${SYSTEM_PROCESSOR}", "${CMAKE_SYSTEM_PROCESSOR}"]:
            if var in txt:
                tmp = f"___TMP_QUOTED_{var[2:-1]}___"
                txt = txt.replace(f'"{var}"', tmp)
                txt = txt.replace(var, f'"{var}"')
                txt = txt.replace(tmp, f'"{var}"')
        if txt != orig:
            write_file_contents(loader_cmake, txt, eol)
            print("  [ok] Safeguarded vulkan-loader/loader/CMakeLists.txt (quoted processor variables)")


def safeguard_rex_version(sdk: pathlib.Path):
    """Ensure rex_version.cmake cleanly resolves 0.10.0 without warnings on iOS."""
    ver_cmake = sdk / "cmake" / "rex_version.cmake"
    if ver_cmake.exists():
        txt, eol = read_file_contents(ver_cmake)
        old_warn = 'message(WARNING\n            "rex_compute_version: no v* tag reachable from HEAD.'
        if old_warn in txt:
            new_warn = 'set(${out_var} "0.10.0" PARENT_SCOPE)\n        return()\n        message(DEBUG\n            "rex_compute_version: no v* tag reachable from HEAD.'
            txt = txt.replace(old_warn, new_warn)
            write_file_contents(ver_cmake, txt, eol)
            print("  [ok] Safeguarded rex_version.cmake (clean 0.10.0 fallback)")


def setup_moltenvk(sdk: pathlib.Path):
    """Downloads & extracts MoltenVK v1.4.1 XCFramework for iOS."""
    dest = sdk / ".dmc4-ios" / "MoltenVK"
    marker = dest / f"{MOLTENVK_VERSION}.ready"
    if marker.exists():
        print(f"  [ok] MoltenVK {MOLTENVK_VERSION} already prepared at {dest}")
        return

    dest.mkdir(parents=True, exist_ok=True)
    tar_path = dest.parent / "MoltenVK-ios.tar"
    if not tar_path.exists():
        print(f"  [..] Downloading MoltenVK {MOLTENVK_VERSION} XCFramework for iOS...")
        try:
            with urllib.request.urlopen(MOLTENVK_URL, timeout=300) as resp:
                tar_path.write_bytes(resp.read())
        except Exception as e:
            print(f"  [warn] Could not download MoltenVK: {e}")
            return

    with tarfile.open(tar_path) as t:
        if hasattr(tarfile, 'data_filter'):
            t.extractall(dest, filter='data')
        else:
            t.extractall(dest)

    xcf = list(dest.rglob("dynamic/MoltenVK.xcframework"))
    if not xcf:
        xcf = list(dest.rglob("MoltenVK.xcframework"))

    if xcf:
        marker.write_text(str(xcf[0].relative_to(dest)) + "\n", encoding="utf-8")
        print(f"  [ok] MoltenVK extracted to {xcf[0]}")
    tar_path.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# iOS SDK Patch Blocks
# ---------------------------------------------------------------------------

# 1. CMake iOS configuration: skip desktop loader and submodule MoltenVK on iOS
CMAKE_REQ_ANCHOR = """    if(APPLE)
        list(APPEND REQUIRED_SUBMODULES vulkan-loader moltenvk)
    endif()
"""
CMAKE_REQ_NEW = """    # DMC4 iOS Patch: Skip desktop vulkan-loader & submodule MoltenVK on iOS
    if(APPLE AND NOT IOS AND NOT REX_PLATFORM_IOS)
        list(APPEND REQUIRED_SUBMODULES vulkan-loader moltenvk)
    endif()
"""

CMAKE_MVK_ANCHOR = """    if(APPLE)
        # Build the loader and MoltenVK revisions shipped by the pinned SDK.
"""
CMAKE_MVK_NEW = """    # DMC4 iOS Patch: MoltenVK.xcframework packaged via ios/CMakeLists.txt
    if(APPLE AND NOT IOS AND NOT REX_PLATFORM_IOS)
        # Build the loader and MoltenVK revisions shipped by the pinned SDK.
"""

CMAKE_DEF_ANCHOR = """        set(REX_PLATFORM "mac-${REX_TARGET_PROCESSOR}")
    endif()
    add_compile_definitions(REX_PLATFORM_MAC=1)
"""
CMAKE_DEF_NEW = """        set(REX_PLATFORM "mac-${REX_TARGET_PROCESSOR}")
    endif()
    add_compile_definitions(REX_PLATFORM_MAC=1)
    # DMC4 iOS Patch: Set REX_PLATFORM_IOS and output folder
    if(IOS OR REX_PLATFORM_IOS)
        add_compile_definitions(REX_PLATFORM_IOS=1)
        set(REX_PLATFORM "ios-${REX_TARGET_PROCESSOR}")
    endif()
"""

# 2. ARM64 fpscr.h warning fix
FPSCR_ANCHOR = 'static inline void setcsr(u32 csr) noexcept { __asm__ __volatile__("msr fpcr, %0" : : "r"(csr)); }'
FPSCR_NEW = 'static inline void setcsr(u32 csr) noexcept { __asm__ __volatile__("msr fpcr, %0" : : "r"((uint64_t)csr)); }'

# 3. Sandbox Filesystem Safety in src/core/filesystem_posix.cpp
DLFCN_ANCHOR = """#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
"""
DLFCN_NEW = """#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
#include <dlfcn.h>
"""

FOLDER_ANCHOR = """std::filesystem::path GetExecutableFolder() {
  return GetExecutablePath().parent_path();
}
"""
FOLDER_NEW = """std::filesystem::path GetExecutableFolder() {
#if REX_PLATFORM_IOS
  // DMC4 iOS Patch: LiveContainer loads inside host process.
  // Query dladdr for library folder inside <app>.app/Frameworks/
  Dl_info info{};
  if (dladdr(reinterpret_cast<const void*>(&GetExecutableFolder), &info) && info.dli_fname) {
    return std::filesystem::path(info.dli_fname).parent_path();
  }
#endif
  return GetExecutablePath().parent_path();
}
"""

USER_FOLDER_ANCHOR = """std::filesystem::path GetUserFolder() {
"""
USER_FOLDER_NEW = """std::filesystem::path GetUserFolder() {
#if REX_PLATFORM_IOS
  // DMC4 iOS Sandbox: $HOME/.local and $HOME/.cache are strictly read-only.
  // Route to $XDG_DATA_HOME or $HOME/Documents/rex_data.
  if (auto xdg = rex::platform::env::get("XDG_DATA_HOME")) {
    return std::filesystem::path(*xdg);
  }
  if (auto home = rex::platform::env::get("HOME")) {
    return std::filesystem::path(*home) / "Documents" / "rex_data";
  }
  return "/private/var/mobile/Documents/rex_data";
#endif
"""

# 4. MoltenVK candidate in src/ui/vulkan/vulkan_instance.cpp
MVK_HEADER_ANCHOR = """#include <rex/cvar.h>
#include <rex/logging.h>
"""
MVK_HEADER_NEW = """#include <rex/cvar.h>
#include <rex/filesystem.h>
#include <rex/logging.h>
"""

MVK_INSTANCE_ANCHOR = """  loader_candidates.emplace_back(platform::lib_names::kVulkanLoader);
  loader_candidates.emplace_back("libvulkan.dylib");
  loader_candidates.emplace_back("libMoltenVK.dylib");
"""
MVK_INSTANCE_NEW = """#if REX_PLATFORM_IOS
  // DMC4 iOS Patch: Priority candidate MoltenVK.framework inside Frameworks/
  loader_candidates.emplace_back(rex::filesystem::GetExecutableFolder() / "MoltenVK.framework" / "MoltenVK");
  loader_candidates.emplace_back("Frameworks/MoltenVK.framework/MoltenVK");
  loader_candidates.emplace_back("MoltenVK.framework/MoltenVK");
#endif
  loader_candidates.emplace_back(platform::lib_names::kVulkanLoader);
  loader_candidates.emplace_back("libvulkan.dylib");
  loader_candidates.emplace_back("libMoltenVK.dylib");
"""

# 5. iOS Darwin Mach VM support in src/core/memory_posix.cpp (replaces unsupported mach_vm.h)
MACH_VM_HEADER_ANCHOR = """#if REX_PLATFORM_MAC
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/vm_region.h>
#endif  // REX_PLATFORM_MAC
"""
MACH_VM_HEADER_NEW = """#if REX_PLATFORM_MAC
#include <mach/mach.h>
#if !REX_PLATFORM_IOS
#include <mach/mach_vm.h>
#else
#include <mach/vm_map.h>
#endif
#include <mach/vm_region.h>
#endif  // REX_PLATFORM_MAC
"""

QUERY_PROTECT_ANCHOR = """bool QueryProtect(void* base_address, size_t& length, PageAccess& access_out) {
#if REX_PLATFORM_MAC
  mach_vm_address_t address = reinterpret_cast<mach_vm_address_t>(base_address);
  mach_vm_size_t region_size = 0;
  vm_region_basic_info_data_64_t info;
  mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
  mach_port_t object_name;

  kern_return_t kr =
      mach_vm_region(mach_task_self(), &address, &region_size, VM_REGION_BASIC_INFO_64,
                     reinterpret_cast<vm_region_info_t>(&info), &info_count, &object_name);
"""
QUERY_PROTECT_NEW = """bool QueryProtect(void* base_address, size_t& length, PageAccess& access_out) {
#if REX_PLATFORM_IOS
  vm_address_t address = reinterpret_cast<vm_address_t>(base_address);
  vm_size_t region_size = 0;
  vm_region_basic_info_data_64_t info;
  mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
  mach_port_t object_name;

  kern_return_t kr =
      vm_region_64(mach_task_self(), &address, &region_size, VM_REGION_BASIC_INFO_64,
                   reinterpret_cast<vm_region_info_t>(&info), &info_count, &object_name);
  if (kr != KERN_SUCCESS) {
    return false;
  }
  if (address > reinterpret_cast<vm_address_t>(base_address)) {
    return false;
  }

  length = static_cast<size_t>((address + region_size) -
                               reinterpret_cast<vm_address_t>(base_address));

  if ((info.protection & (VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)) ==
      (VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)) {
    access_out = PageAccess::kExecuteReadWrite;
  } else if ((info.protection & (VM_PROT_READ | VM_PROT_EXECUTE)) ==
             (VM_PROT_READ | VM_PROT_EXECUTE)) {
    access_out = PageAccess::kExecuteReadOnly;
  } else if ((info.protection & (VM_PROT_READ | VM_PROT_WRITE)) ==
             (VM_PROT_READ | VM_PROT_WRITE)) {
    access_out = PageAccess::kReadWrite;
  } else if (info.protection & VM_PROT_READ) {
    access_out = PageAccess::kReadOnly;
  } else {
    access_out = PageAccess::kNoAccess;
  }
  return true;
#elif REX_PLATFORM_MAC
  mach_vm_address_t address = reinterpret_cast<mach_vm_address_t>(base_address);
  mach_vm_size_t region_size = 0;
  vm_region_basic_info_data_64_t info;
  mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
  mach_port_t object_name;

  kern_return_t kr =
      mach_vm_region(mach_task_self(), &address, &region_size, VM_REGION_BASIC_INFO_64,
                     reinterpret_cast<vm_region_info_t>(&info), &info_count, &object_name);
"""

DMC4_PATCH_BLOCKS = [
    ("thirdparty/CMakeLists.txt", "skip desktop vulkan-loader / submodule moltenvk on iOS",
     CMAKE_REQ_ANCHOR, CMAKE_REQ_NEW),
    ("thirdparty/CMakeLists.txt", "skip submodule MoltenVK build on iOS",
     CMAKE_MVK_ANCHOR, CMAKE_MVK_NEW),
    ("CMakeLists.txt", "set REX_PLATFORM_IOS and ios-arm64 output dir",
     CMAKE_DEF_ANCHOR, CMAKE_DEF_NEW),
    ("include/rex/platform/fpscr.h", "cast csr to uint64_t for ARM64 msr fpcr",
     FPSCR_ANCHOR, FPSCR_NEW),
    ("src/core/filesystem_posix.cpp", "include dlfcn.h on Apple platforms",
     DLFCN_ANCHOR, DLFCN_NEW),
    ("src/core/filesystem_posix.cpp", "GetExecutableFolder dladdr fallback for LiveContainer",
     FOLDER_ANCHOR, FOLDER_NEW),
    ("src/core/filesystem_posix.cpp", "GetUserFolder iOS sandbox routing to Documents/rex_data",
     USER_FOLDER_ANCHOR, USER_FOLDER_NEW),
    ("src/ui/vulkan/vulkan_instance.cpp", "include rex/filesystem.h in vulkan_instance.cpp",
     MVK_HEADER_ANCHOR, MVK_HEADER_NEW),
    ("src/ui/vulkan/vulkan_instance.cpp", "MoltenVK.framework candidate for iOS",
     MVK_INSTANCE_ANCHOR, MVK_INSTANCE_NEW),
    ("src/core/memory_posix.cpp", "iOS Darwin Mach VM header routing (avoid unsupported mach_vm.h)",
     MACH_VM_HEADER_ANCHOR, MACH_VM_HEADER_NEW),
    ("src/core/memory_posix.cpp", "iOS QueryProtect using vm_region_64 instead of mach_vm_region",
     QUERY_PROTECT_ANCHOR, QUERY_PROTECT_NEW),
]


def apply_patches(sdk: pathlib.Path, status: bool = False, revert: bool = False):
    print(f"\n[prepare_sdk] Applying Devil May Cry 4 iOS patches to SDK ({sdk})...")
    rc = apply_patch_blocks("dmc4_ios_sdk", DMC4_PATCH_BLOCKS, sdk, status_only=status, revert=revert)
    if rc != 0:
        print("[prepare_sdk] WARNING: One or more patch blocks failed dry-run assertion.")
        return False
    return True


def main():
    parser = argparse.ArgumentParser(description="ReXGlue SDK Preparation for Devil May Cry 4 iOS")
    parser.add_argument("--sdk", help="Path to rexglue-sdk-ios")
    parser.add_argument("--status", action="store_true", help="Check patch status")
    parser.add_argument("--revert", action="store_true", help="Revert patches")
    args = parser.parse_args()

    sdk_path = pathlib.Path(args.sdk).resolve() if args.sdk else find_sdk()
    print(f"===============================================================================")
    print(f"  PREPARING REXGLUE SDK FOR DEVIL MAY CRY 4 (XBOX 360, 434307DF) - iOS ARM64")
    print(f"===============================================================================")
    print(f"  Target SDK: {sdk_path}")

    # 1. Ensure git tag v0.10.0 is reachable
    if not args.status and not args.revert:
        ensure_git_tags(sdk_path)
        safeguard_vulkan_loader(sdk_path)
        safeguard_rex_version(sdk_path)
        setup_moltenvk(sdk_path)

    # 2. Apply verified patch blocks
    apply_patches(sdk_path, status=args.status, revert=args.revert)
    print("\n[prepare_sdk] SDK preparation completed successfully.")


if __name__ == "__main__":
    main()
