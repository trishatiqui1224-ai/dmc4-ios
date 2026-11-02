# =============================================================================
#  Devil May Cry 4 (Xbox 360, Title ID: 434307DF, Capcom MT Framework)
#  iOS Application Target (ARM64 Native, iOS 16.0+)
# =============================================================================

cmake_minimum_required(VERSION 3.25)

if(NOT CMAKE_SYSTEM_NAME)
    set(CMAKE_SYSTEM_NAME "iOS")
endif()
if(NOT CMAKE_SYSTEM_PROCESSOR)
    set(CMAKE_SYSTEM_PROCESSOR "arm64")
endif()
if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64")
endif()
if(NOT CMAKE_OSX_SYSROOT)
    set(CMAKE_OSX_SYSROOT "iphoneos")
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0")
endif()

set(REX_PLATFORM_IOS 1 CACHE BOOL "Build for iOS platform" FORCE)
add_compile_definitions(REX_PLATFORM_IOS=1)

# Prefer clang from iphoneos SDK toolchain
if(APPLE AND NOT CMAKE_C_COMPILER)
    execute_process(
        COMMAND xcrun --sdk iphoneos --find clang
        OUTPUT_VARIABLE _IOS_CLANG
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_IOS_CLANG AND EXISTS "${_IOS_CLANG}")
        set(CMAKE_C_COMPILER "${_IOS_CLANG}" CACHE FILEPATH "C compiler" FORCE)
    endif()
endif()
if(APPLE AND NOT CMAKE_CXX_COMPILER)
    execute_process(
        COMMAND xcrun --sdk iphoneos --find clang++
        OUTPUT_VARIABLE _IOS_CLANGXX
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_IOS_CLANGXX AND EXISTS "${_IOS_CLANGXX}")
        set(CMAKE_CXX_COMPILER "${_IOS_CLANGXX}" CACHE FILEPATH "CXX compiler" FORCE)
    endif()
endif()

project(dmc4_ios_app LANGUAGES C CXX OBJC OBJCXX ASM)

if(NOT IOS)
    message(FATAL_ERROR "This CMakeLists.txt is for iOS. Configure with cmake --preset ios")
endif()

set(DMC4_REPO "${CMAKE_CURRENT_SOURCE_DIR}/.." CACHE PATH "Devil May Cry 4 iOS repository root")
set(DMC4_SDK "${DMC4_REPO}/../rexglue-sdk-ios" CACHE PATH "ReXGlue SDK prepared for iOS")
set(DMC4_BUNDLE_ID "com.recomp.dmc4.ios" CACHE STRING "App bundle identifier")
set(DMC4_GEN_DIR "${DMC4_REPO}/generated/default" CACHE PATH "Generated code directory")
set(DMC4_JOBS_RECOMP "2" CACHE STRING "Parallel recompilation jobs")
get_filename_component(DMC4_REPO "${DMC4_REPO}" ABSOLUTE)
get_filename_component(DMC4_SDK "${DMC4_SDK}" ABSOLUTE)

# Locate MoltenVK.framework
set(_mvk_marker "${DMC4_SDK}/.dmc4-ios/MoltenVK/v1.4.1.ready")
if(EXISTS "${_mvk_marker}")
    file(STRINGS "${_mvk_marker}" _mvk_rel LIMIT_COUNT 1)
    set(DMC4_MOLTENVK_FW "${DMC4_SDK}/.dmc4-ios/MoltenVK/${_mvk_rel}/ios-arm64/MoltenVK.framework")
endif()

if(NOT EXISTS "${DMC4_MOLTENVK_FW}/MoltenVK")
    file(GLOB_RECURSE _found_mvk
        "${DMC4_SDK}/.dmc4-ios/*/ios-arm64/MoltenVK.framework"
        "${DMC4_SDK}/.dmc4-ios/MoltenVK.framework"
        "${DMC4_REPO}/ios/Frameworks/MoltenVK.framework"
    )
    if(_found_mvk)
        list(GET _found_mvk 0 DMC4_MOLTENVK_FW)
    endif()
endif()

if(EXISTS "${DMC4_MOLTENVK_FW}")
    message(STATUS "[DMC4] Found MoltenVK.framework at ${DMC4_MOLTENVK_FW}")
else()
    message(STATUS "[DMC4] MoltenVK.framework marker not yet created (tools/ios/prepare_sdk.py will prepare it)")
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)

set(REXGLUE_ENABLE_TRACY OFF CACHE BOOL "" FORCE)
set(REXGLUE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(REXGLUE_USE_VULKAN ON CACHE BOOL "" FORCE)
set(REXGLUE_USE_D3D12 OFF CACHE BOOL "" FORCE)
set(REXGLUE_ENABLE_DESKTOP_SDL_BACKENDS OFF CACHE BOOL "" FORCE)

if(EXISTS "${DMC4_SDK}/CMakeLists.txt")
    add_subdirectory("${DMC4_SDK}" rexglue-sdk)
endif()

# Header-only interface library for SDK dependencies
add_library(dmc4_headers INTERFACE)
if(TARGET imgui)
    target_include_directories(dmc4_headers INTERFACE $<TARGET_PROPERTY:imgui,INTERFACE_INCLUDE_DIRECTORIES>)
endif()
if(TARGET Vulkan::Headers)
    target_link_libraries(dmc4_headers INTERFACE Vulkan::Headers)
endif()
if(TARGET GPUOpen::VulkanMemoryAllocator)
    target_link_libraries(dmc4_headers INTERFACE GPUOpen::VulkanMemoryAllocator)
endif()
if(TARGET spirv-tools-headers)
    target_link_libraries(dmc4_headers INTERFACE spirv-tools-headers)
endif()

# -----------------------------------------------------------------------------
#  Generated Game Code (PowerPC to ARM64 C++)
# -----------------------------------------------------------------------------
set(DMC4_WITH_GAME ON)
if(EXISTS "${DMC4_GEN_DIR}/sources.cmake")
    include("${DMC4_GEN_DIR}/sources.cmake")
    if(GENERATED_SOURCES)
        add_library(dmc4_recomp STATIC ${GENERATED_SOURCES})
        target_include_directories(dmc4_recomp PRIVATE
            "${DMC4_REPO}"
            "${DMC4_REPO}/src"
            "${DMC4_GEN_DIR}"
            "${CMAKE_CURRENT_SOURCE_DIR}/src"
        )
        if(TARGET rex::runtime)
            target_link_libraries(dmc4_recomp PUBLIC rex::runtime dmc4_headers)
            rexglue_apply_target_settings(dmc4_recomp)
        endif()
        target_compile_options(dmc4_recomp PRIVATE -gline-tables-only -Wno-unused-variable)
        set_property(GLOBAL APPEND PROPERTY JOB_POOLS recomp=${DMC4_JOBS_RECOMP})
        set_target_properties(dmc4_recomp PROPERTIES JOB_POOL_COMPILE recomp)
        message(STATUS "[DMC4] Registered recompiled game sources from ${DMC4_GEN_DIR}")
    endif()
endif()

# -----------------------------------------------------------------------------
#  Application Target (DevilMayCry4.app)
# -----------------------------------------------------------------------------
set(DMC4_VERSION "1.0.0")
set(DMC4_VERSION_CODE "1")
set(DMC4_DISPLAY_NAME "Devil May Cry 4")
set(DMC4_IOS_MIN "${CMAKE_OSX_DEPLOYMENT_TARGET}")
set(DMC4_EXECUTABLE "DevilMayCry4")

configure_file("${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
               "${CMAKE_CURRENT_BINARY_DIR}/Info.plist" @ONLY)

set(DMC4_APP_SOURCES
    src/ios_main.mm
    src/launcher.mm
    src/dmc4_app.mm
    src/touch_controls.mm
    src/audio/coreaudio_driver.mm
    src/vfs/iso_piece_reader.mm
    src/boot_trace.cpp
    src/battery.mm
    src/display_rate.mm
    src/memory_report.mm
    src/lifecycle.mm
    src/ingame_options.mm
    src/probe.cpp
    src/probe_apple.mm
    src/probe_memory.cpp
    src/gpu_capture.mm
    src/adaptive_qos.cpp
    src/frame_clock.cpp
    src/native_metal_probe.mm
    src/save_manager.mm
    src/save_import.cpp
    src/save_convert.cpp
    src/achievements_export.cpp
    ${DMC4_REPO}/src/dmc4_kernel_stubs.cpp
)

add_executable(dmc4_app MACOSX_BUNDLE ${DMC4_APP_SOURCES})
set_target_properties(dmc4_app PROPERTIES
    OUTPUT_NAME "${DMC4_EXECUTABLE}"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist"
    INSTALL_RPATH "@loader_path/Frameworks"
)

target_compile_options(dmc4_app PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_include_directories(dmc4_app PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${DMC4_REPO}"
    "${DMC4_REPO}/src"
    "${DMC4_SDK}"
    "${DMC4_SDK}/include"
    "${DMC4_SDK}/src"
    "${DMC4_GEN_DIR}"
)

set(DMC4_GAME_LANGUAGE "1" CACHE STRING "DMC4 game language ID (1=English)")

target_compile_definitions(dmc4_app PRIVATE
    REXGLUE_BUILD_CONFIG="$<CONFIG>"
    DMC4_WITH_GAME=1
    DMC4_GAME_LANGUAGE="${DMC4_GAME_LANGUAGE}"
    TITLE_ID="434307DF"
)

target_link_libraries(dmc4_app PRIVATE
    dmc4_headers
    "-framework Foundation"
    "-framework UIKit"
    "-framework Metal"
    "-framework MetalFX"
    "-framework QuartzCore"
    "-framework CoreImage"
    "-framework UniformTypeIdentifiers"
    "-framework AudioToolbox"
    "-framework AVFoundation"
    "-framework GameController"
    z
)

if(TARGET rex::runtime)
    target_link_libraries(dmc4_app PRIVATE rex::runtime)
endif()

if(TARGET dmc4_recomp)
    target_link_libraries(dmc4_app PRIVATE dmc4_recomp)
endif()

if(TARGET rexgpu-xenos)
    add_dependencies(dmc4_app rexgpu-xenos)
endif()

# -----------------------------------------------------------------------------
#  Packaging & Code Signing Target (Ad-Hoc for LiveContainer / Sideloading)
# -----------------------------------------------------------------------------
set(_app "$<TARGET_BUNDLE_DIR:dmc4_app>")
set(_fw "${_app}/Frameworks")

if(TARGET rexruntime)
    set(_copy_rexruntime COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:rexruntime>" "${_fw}/")
    set(_sign_rexruntime COMMAND codesign --force --sign - --timestamp=none "${_fw}/$<TARGET_FILE_NAME:rexruntime>" 2>/dev/null || true)
    set(_dep_rexruntime rexruntime)
else()
    set(_copy_rexruntime COMMAND ${CMAKE_COMMAND} -E true)
    set(_sign_rexruntime COMMAND ${CMAKE_COMMAND} -E true)
    set(_dep_rexruntime "")
endif()

if(TARGET rexgpu-xenos)
    set(_copy_rexgpu COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:rexgpu-xenos>" "${_fw}/")
    set(_sign_rexgpu COMMAND codesign --force --sign - --timestamp=none "${_fw}/$<TARGET_FILE_NAME:rexgpu-xenos>" 2>/dev/null || true)
    set(_dep_rexgpu rexgpu-xenos)
else()
    set(_copy_rexgpu COMMAND ${CMAKE_COMMAND} -E true)
    set(_sign_rexgpu COMMAND ${CMAKE_COMMAND} -E true)
    set(_dep_rexgpu "")
endif()

if(EXISTS "${DMC4_MOLTENVK_FW}")
    set(_copy_mvk_cmd COMMAND ${CMAKE_COMMAND} -E copy_directory "${DMC4_MOLTENVK_FW}" "${_fw}/MoltenVK.framework")
    set(_sign_mvk_cmd COMMAND codesign --force --sign - --timestamp=none "${_fw}/MoltenVK.framework" 2>/dev/null || true)
else()
    set(_copy_mvk_cmd COMMAND ${CMAKE_COMMAND} -E true)
    set(_sign_mvk_cmd COMMAND ${CMAKE_COMMAND} -E true)
endif()

add_custom_target(dmc4_package ALL
    COMMAND ${CMAKE_COMMAND} -E make_directory "${_fw}"
    ${_copy_rexruntime}
    ${_copy_rexgpu}
    ${_copy_mvk_cmd}
    COMMAND xcrun actool "${CMAKE_CURRENT_SOURCE_DIR}/resources/Assets.xcassets"
            --compile "${_app}" --platform iphoneos
            --minimum-deployment-target "${CMAKE_OSX_DEPLOYMENT_TARGET}"
            --target-device iphone --target-device ipad --app-icon AppIcon
            --output-partial-info-plist "${CMAKE_CURRENT_BINARY_DIR}/actool-partial.plist"
            --output-format human-readable-text --errors --warnings || true
    COMMAND xattr -cr "${_app}" || true
    ${_sign_mvk_cmd}
    ${_sign_rexruntime}
    ${_sign_rexgpu}
    COMMAND codesign --force --sign - --timestamp=none
            --entitlements "${CMAKE_CURRENT_SOURCE_DIR}/dmc4.entitlements" "${_app}" || true
    COMMENT "[DMC4] Packaging and ad-hoc signing DevilMayCry4.app"
    VERBATIM
)
add_dependencies(dmc4_package dmc4_app ${_dep_rexruntime} ${_dep_rexgpu})

# -----------------------------------------------------------------------------
#  IPA Generation Target (Unsigned IPA for LiveContainer / SideStore / AltStore)
# -----------------------------------------------------------------------------
add_custom_target(ipa
    COMMAND ${CMAKE_COMMAND} -E rm -rf "${CMAKE_CURRENT_BINARY_DIR}/ipa"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/ipa/Payload"
    COMMAND ditto "${_app}" "${CMAKE_CURRENT_BINARY_DIR}/ipa/Payload/DevilMayCry4.app"
    COMMAND ${CMAKE_COMMAND} -E rm -f "${CMAKE_CURRENT_BINARY_DIR}/DevilMayCry4.ipa"
    COMMAND ${CMAKE_COMMAND} -E rm -f "${CMAKE_CURRENT_BINARY_DIR}/DMC4-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E chdir "${CMAKE_CURRENT_BINARY_DIR}/ipa"
            ditto -c -k --sequesterRsrc --keepParent Payload "${CMAKE_CURRENT_BINARY_DIR}/DMC4-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/DMC4-iOS-unsigned.ipa"
            "${CMAKE_CURRENT_BINARY_DIR}/DevilMayCry4.ipa"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${DMC4_REPO}/build"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${DMC4_REPO}/dist"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/DMC4-iOS-unsigned.ipa"
            "${DMC4_REPO}/build/DMC4-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/DMC4-iOS-unsigned.ipa"
            "${DMC4_REPO}/dist/DMC4-iOS-unsigned.ipa"
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/DevilMayCry4.ipa"
            "${DMC4_REPO}/dist/DevilMayCry4.ipa"
    COMMENT "[DMC4] Generated unsigned IPA package at dist/DMC4-iOS-unsigned.ipa"
    VERBATIM
)
add_dependencies(ipa dmc4_package)
