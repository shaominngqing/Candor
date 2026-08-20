#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
app_bundle="$project_root/dist/Candor.app"
contents_dir="$app_bundle/Contents"
codesign_identity="${CODESIGN_IDENTITY:-"-"}"

swift build -c release --package-path "$project_root"

/bin/rm -rf "$app_bundle"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
install -m 755 "$project_root/.build/release/Candor" "$contents_dir/MacOS/Candor"
install -m 644 "$project_root/AppResources/Info.plist" "$contents_dir/Info.plist"
install -m 644 "$project_root/AppResources/PrivacyInfo.xcprivacy" "$contents_dir/Resources/PrivacyInfo.xcprivacy"
install -m 644 "$project_root/AppResources/CandorIcon.icns" "$contents_dir/Resources/CandorIcon.icns"

codesign_options=(--force --sign "$codesign_identity")
if [[ "$codesign_identity" != "-" ]]; then
    codesign_options+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${codesign_options[@]}" "$app_bundle"
/usr/bin/codesign --verify --deep --strict "$app_bundle"

echo "$app_bundle"
