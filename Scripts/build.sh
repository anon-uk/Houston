#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUTPUT_DIR="${HOUSTON_OUTPUT_DIR:-$ROOT/..}"
DEST="${1:-$OUTPUT_DIR/Houston.app}"
BUILD="${HOUSTON_BUILD_DIR:-$ROOT/../../work/build}"
SDK="${HOUSTON_SPARKLE_DIR:-$ROOT/../../work/Sparkle}"
HOUSTON_SPARKLE_DIR="$SDK" "$ROOT/Scripts/setup-sparkle.sh"
mkdir -p "$BUILD" "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
xcrun clang -O2 -mmacosx-version-min=26.0 -c "$ROOT/Native/Metrics.c" -o "$BUILD/Metrics.o"
xcrun swiftc -parse-as-library -O -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path "$BUILD/cache" -import-objc-header "$ROOT/Native/Metrics.h" "$ROOT/Sources/TaskManager.swift" "$ROOT/Sources/GraphGeometry.swift" "$ROOT/Sources/MenuGadgetLayout.swift" "$ROOT/Sources/Updater.swift" -F "$SDK" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks "$BUILD/Metrics.o" -o "$DEST/Contents/MacOS/Houston" -framework SwiftUI -framework AppKit -framework Charts
cp "$ROOT/Assets/TaskManager.icns" "$DEST/Contents/Resources/TaskManager.icns"
mkdir -p "$DEST/Contents/Frameworks"
ditto --norsrc "$SDK/Sparkle.framework" "$DEST/Contents/Frameworks/Sparkle.framework"
cp "$ROOT/AI_DISCLOSURE.md" "$ROOT/SPARKLE-LICENSE.txt" "$DEST/Contents/Resources/"
cp "$ROOT/LICENSE" "$DEST/Contents/Resources/LICENSE"
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$DEST/Contents/Resources/THIRD-PARTY-NOTICES.md"
cat > "$DEST/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Houston</string><key>CFBundleIdentifier</key><string>dev.native.TaskManager</string><key>CFBundleIconFile</key><string>TaskManager</string><key>CFBundleName</key><string>Houston</string><key>CFBundleDisplayName</key><string>Houston</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.4</string><key>CFBundleVersion</key><string>5</string><key>LSMinimumSystemVersion</key><string>26.0</string><key>SUFeedURL</key><string>https://raw.githubusercontent.com/anon-uk/Houston/main/appcast.xml</string><key>SUPublicEDKey</key><string>TdhxwhhH3HIFBQOiWd//NSssfxaHCJvnfRshWQvBOdY=</string><key>SUEnableAutomaticChecks</key><false/><key>SUEnableSystemProfiling</key><false/><key>SUScheduledCheckInterval</key><integer>86400</integer><key>SUAllowsAutomaticUpdates</key><true/><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
STAGE=$(mktemp -d /private/tmp/native-taskmanager.XXXXXX)
ditto --norsrc "$DEST" "$STAGE/Houston.app"
xattr -cr "$STAGE/Houston.app"
codesign --force --sign - "$STAGE/Houston.app"
codesign --verify --deep --strict "$STAGE/Houston.app"
ditto --norsrc "$STAGE/Houston.app" "$DEST"
ditto -c -k --norsrc --keepParent "$STAGE/Houston.app" "$OUTPUT_DIR/Houston-Mac.zip"
CHECK=$(mktemp -d /private/tmp/native-taskmanager-check.XXXXXX)
ditto -x -k "$OUTPUT_DIR/Houston-Mac.zip" "$CHECK"
codesign --verify --deep --strict "$CHECK/Houston.app"
unzip -t "$OUTPUT_DIR/Houston-Mac.zip" > /dev/null
print "Verified app and ZIP: $OUTPUT_DIR/Houston-Mac.zip"
