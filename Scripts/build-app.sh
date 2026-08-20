#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
app_bundle="$project_root/dist/Candor.app"
contents_dir="$app_bundle/Contents"

swift build -c release --package-path "$project_root"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
install -m 755 "$project_root/.build/release/YuJing" "$contents_dir/MacOS/YuJing"
install -m 644 "$project_root/AppResources/Info.plist" "$contents_dir/Info.plist"
install -m 644 "$project_root/AppResources/PrivacyInfo.xcprivacy" "$contents_dir/Resources/PrivacyInfo.xcprivacy"
install -m 644 "$project_root/AppResources/CandorIcon.icns" "$contents_dir/Resources/CandorIcon.icns"

/usr/bin/codesign --force --deep --sign - "$app_bundle"
/usr/bin/codesign --verify --deep --strict "$app_bundle"

echo "$app_bundle"
