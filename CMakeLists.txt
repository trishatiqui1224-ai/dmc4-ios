# =============================================================================
#  Devil May Cry 4 (Xbox 360, Title ID: 434307DF, Capcom MT Framework)
#  Apple Silicon iOS/iPadOS Static Recompilation Port (ARM64 Native)
# =============================================================================

cmake_minimum_required(VERSION 3.25)

# Defaults for iOS target before project()
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

project(dmc4_ios LANGUAGES C CXX OBJC OBJCXX ASM)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_C_STANDARD 11)

add_subdirectory(ios)
