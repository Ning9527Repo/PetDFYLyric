#!/bin/sh
set -euo pipefail
cd "$(dirname "$0")/.."
THEOS="${THEOS:-}"
: "${THEOS:?Set THEOS}"
test -d "$THEOS/sdks/iPhoneOS16.5.sdk"
SDK="$THEOS/sdks/iPhoneOS16.5.sdk"
SUPPORT="$THEOS/vendor/lib"
mkdir -p build stage/DEBIAN stage/Library/MobileSubstrate/DynamicLibraries
# Host test (macOS clang supports ObjC ARC)
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter tests/LyricLogic.m -framework Foundation -o build/lyric-logic-test
./build/lyric-logic-test | tee build/lyric-logic.txt
# arm64e dynamic library
clang -target arm64e-apple-ios15.0 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -fobjc-arc -fvisibility=hidden -O2 -dynamiclib \
  -IHeaders -ISources -I"$THEOS/vendor/include" -DAPELIN_BUILD_ID='"local"' \
  Hooks/PDLyricMain.m Sources/PDLyricController.m \
  -L"$SUPPORT" -lsubstrate -framework UIKit -framework Foundation -framework CoreFoundation -framework QuartzCore -framework Security \
  -o build/PDLyric.dylib
ldid -S build/PDLyric.dylib
cp build/PDLyric.dylib stage/Library/MobileSubstrate/DynamicLibraries/
cp layout/Library/MobileSubstrate/DynamicLibraries/PDLyric.plist stage/Library/MobileSubstrate/DynamicLibraries/
sed "s/^Architecture:.*/Architecture: iphoneos-arm64e/" control > stage/DEBIAN/control
dpkg-deb -b --root-owner-group stage packages/PDLyric_1.0.0_iphoneos-arm64e.deb
dpkg-deb -c packages/PDLyric_1.0.0_iphoneos-arm64e.deb | tee build/package-listing.txt
shasum -a 256 packages/*.deb > build/SHA256SUMS
