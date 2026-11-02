#!/usr/bin/env bash
# =============================================================================
#  Devil May Cry 4 (Xbox 360, Title ID: 434307DF) - Local & CI Build Script
#  Compiles Native ARM64 iOS App & Packages Unsigned IPA
# =============================================================================
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

echo "==============================================================================="
echo "  DEVIL MAY CRY 4 (TITLE ID: 434307DF) - iOS ARM64 BUILD PIPELINE"
echo "==============================================================================="

# 1. Generate Studio AppIcon & Asset Catalog
echo "[1/5] Generating Studio AppIcon..."
python3 tools/generate_appicon.py

# 2. Stage DMC4 default.xex & Run Static Analysis Codegen
echo "[2/5] Running DMC4 Static Recompilation Pipeline..."
python3 tools/build_dmc4_codegen.py

# 3. Prepare ReXGlue iOS SDK & MoltenVK
echo "[3/5] Preparing ReXGlue iOS SDK & MoltenVK..."
python3 tools/ios/prepare_sdk.py --sdk "${REPO_ROOT}/../rexglue-sdk-ios"

# 4. Configure CMake with iOS ARM64 Toolchain
echo "[4/5] Configuring CMake for iOS ARM64..."
cd "${REPO_ROOT}/ios"

export CC="$(xcrun --sdk iphoneos --find clang 2>/dev/null || which clang)"
export CXX="$(xcrun --sdk iphoneos --find clang++ 2>/dev/null || which clang++)"
export OBJC="${CC}"
export OBJCXX="${CXX}"

cmake --preset ios \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DREX_PLATFORM_IOS=1 \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_OBJC_COMPILER="${CC}" \
  -DCMAKE_OBJCXX_COMPILER="${CXX}" \
  -DCMAKE_ASM_COMPILER="${CC}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=""

# 5. Compile and Package IPA
echo "[5/5] Building DevilMayCry4.app and packaging unsigned IPA..."
cmake --build --preset ios --target ipa -- -j 4

echo "==============================================================================="
echo "  BUILD SUCCEEDED! Artifacts located at: ${REPO_ROOT}/dist"
echo "==============================================================================="
ls -la "${REPO_ROOT}/dist" || true
