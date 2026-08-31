#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
app_bundle="$project_root/dist/Candor.app"
contents_dir="$app_bundle/Contents"
codesign_identity="${CODESIGN_IDENTITY:-"-"}"

swift build -c release --package-path "$project_root"

/bin/rm -rf "$app_bundle"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$contents_dir/Frameworks"
install -m 755 "$project_root/.build/release/Candor" "$contents_dir/MacOS/Candor"
install -m 644 "$project_root/AppResources/Info.plist" "$contents_dir/Info.plist"
install -m 644 "$project_root/AppResources/PrivacyInfo.xcprivacy" "$contents_dir/Resources/PrivacyInfo.xcprivacy"
install -m 644 "$project_root/AppResources/CandorIcon.icns" "$contents_dir/Resources/CandorIcon.icns"
install -m 644 "$project_root/AppResources/Sparkle-LICENSE.txt" "$contents_dir/Resources/Sparkle-LICENSE.txt"

sparkle_framework=$(find "$project_root/.build/artifacts" -type d -name Sparkle.framework -print -quit)
if [[ -z "$sparkle_framework" ]]; then
    echo "Sparkle.framework was not resolved by Swift Package Manager" >&2
    exit 66
fi
/usr/bin/ditto "$sparkle_framework" "$contents_dir/Frameworks/Sparkle.framework"

architecture=$(/usr/bin/lipo -archs "$contents_dir/MacOS/Candor")
case "$architecture" in
    arm64 | x86_64) ;;
    *)
        echo "Expected a single supported architecture, found: $architecture" >&2
        exit 65
        ;;
esac
/usr/libexec/PlistBuddy -c \
    "Set :SUFeedURL https://github.com/shaominngqing/Candor/releases/latest/download/appcast-${architecture}.xml" \
    "$contents_dir/Info.plist"

codesign_options=(--force --sign "$codesign_identity")
if [[ "$codesign_identity" != "-" ]]; then
    sparkle_version_dir="$contents_dir/Frameworks/Sparkle.framework/Versions/B"
    sparkle_sign_options=(--force --sign "$codesign_identity" --options runtime --timestamp)
    /usr/bin/codesign "${sparkle_sign_options[@]}" "$sparkle_version_dir/XPCServices/Installer.xpc"
    /usr/bin/codesign \
        "${sparkle_sign_options[@]}" \
        --preserve-metadata=entitlements \
        "$sparkle_version_dir/XPCServices/Downloader.xpc"
    /usr/bin/codesign "${sparkle_sign_options[@]}" "$sparkle_version_dir/Autoupdate"
    /usr/bin/codesign "${sparkle_sign_options[@]}" "$sparkle_version_dir/Updater.app"
    /usr/bin/codesign "${sparkle_sign_options[@]}" "$contents_dir/Frameworks/Sparkle.framework"
    codesign_options+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${codesign_options[@]}" "$app_bundle"
/usr/bin/codesign --verify --deep --strict "$app_bundle"

echo "$app_bundle"
