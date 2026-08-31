#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
architecture="${1:-$(uname -m)}"
artifacts_dir="${2:-"$project_root/artifacts"}"
app_bundle="$project_root/dist/Candor.app"
executable="$app_bundle/Contents/MacOS/Candor"
codesign_identity="${CODESIGN_IDENTITY:-"-"}"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$project_root/AppResources/Info.plist")
base_name="Candor-${version}-macOS-${architecture}"
zip_path="$artifacts_dir/${base_name}.zip"
dmg_path="$artifacts_dir/${base_name}.dmg"
staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/candor-dmg.XXXXXX")
layout_dir=$(mktemp -d "${TMPDIR:-/tmp}/candor-layout.XXXXXX")
layout_dmg="$layout_dir/Candor-layout.dmg"
verification_root=$(mktemp -d "${TMPDIR:-/tmp}/candor-verify.XXXXXX")
verification_mount="$verification_root/mount"
background_renderer="$project_root/Scripts/render-dmg-background.swift"
layout_script="$project_root/Scripts/layout-dmg.applescript"
layout_mount=""
layout_device=""
is_layout_mounted=false
is_verification_mounted=false

cleanup() {
    if [[ "$is_layout_mounted" == true ]]; then
        /usr/bin/hdiutil detach -quiet "${layout_mount:-$layout_device}" || true
    fi
    if [[ "$is_verification_mounted" == true ]]; then
        /usr/bin/hdiutil detach -quiet "$verification_mount" || true
    fi
    /bin/rm -R -- "$staging_dir" "$layout_dir" "$verification_root"
}
trap cleanup EXIT

case "$architecture" in
    arm64 | x86_64) ;;
    *)
        echo "Unsupported architecture: $architecture" >&2
        exit 64
        ;;
esac

guard_file() {
    if [[ ! -e "$1" ]]; then
        echo "Missing required file: $1" >&2
        exit 66
    fi
}

guard_file "$app_bundle"
guard_file "$executable"
guard_file "$background_renderer"
guard_file "$layout_script"
/usr/bin/file "$executable" | /usr/bin/grep -q "$architecture"
/usr/bin/codesign --verify --deep --strict "$app_bundle"

mkdir -p "$artifacts_dir"
/bin/rm -f "$zip_path" "$zip_path.sha256" "$dmg_path" "$dmg_path.sha256"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_path"

/usr/bin/ditto "$app_bundle" "$staging_dir/Candor.app"
/bin/ln -s /Applications "$staging_dir/Applications"
/bin/mkdir -p "$staging_dir/.background"
/usr/bin/xcrun swift "$background_renderer" "$staging_dir/.background/CandorDMG.png"
/usr/bin/chflags hidden "$staging_dir/.background"
/usr/bin/touch "$staging_dir/.metadata_never_index"
/usr/bin/hdiutil create \
    -quiet \
    -volname "Candor $version" \
    -srcfolder "$staging_dir" \
    -format UDRW \
    -ov \
    "$layout_dmg"

attach_output=$(/usr/bin/hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    -nobrowse \
    -mountrandom /Volumes \
    "$layout_dmg")
layout_device=$(printf '%s\n' "$attach_output" | /usr/bin/awk '/^\/dev\// { print $1; exit }')
layout_mount=$(printf '%s\n' "$attach_output" | /usr/bin/awk -F '\t' '$NF ~ /^\/Volumes\// { print $NF; exit }')
is_layout_mounted=true
guard_file "$layout_mount"
disk_name=$(/usr/bin/basename "$layout_mount")
/usr/bin/osascript "$layout_script" "$disk_name" "$layout_mount"
/bin/sync
for _ in {1..10}; do
    [[ -f "$layout_mount/.DS_Store" ]] && break
    /bin/sleep 1
done
guard_file "$layout_mount/.DS_Store"
/usr/bin/hdiutil detach -quiet "$layout_mount"
is_layout_mounted=false

/usr/bin/hdiutil convert \
    -quiet \
    "$layout_dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$dmg_path"

if [[ "$codesign_identity" != "-" ]]; then
    /usr/bin/codesign --force --sign "$codesign_identity" --timestamp "$dmg_path"
    /usr/bin/codesign --verify --verbose=2 "$dmg_path"
fi

/usr/bin/hdiutil verify -quiet "$dmg_path"
/bin/mkdir -p "$verification_mount"
is_verification_mounted=true
/usr/bin/hdiutil attach -quiet -nobrowse -readonly -mountpoint "$verification_mount" "$dmg_path"
guard_file "$verification_mount/Candor.app"
guard_file "$verification_mount/Applications"
guard_file "$verification_mount/.background/CandorDMG.png"
guard_file "$verification_mount/.DS_Store"
[[ "$(/usr/bin/readlink "$verification_mount/Applications")" == "/Applications" ]]
[[ "$(/usr/bin/sips -g pixelWidth "$verification_mount/.background/CandorDMG.png" | /usr/bin/awk '/pixelWidth:/ { print $2 }')" == "660" ]]
[[ "$(/usr/bin/sips -g pixelHeight "$verification_mount/.background/CandorDMG.png" | /usr/bin/awk '/pixelHeight:/ { print $2 }')" == "420" ]]
/usr/bin/file "$verification_mount/Candor.app/Contents/MacOS/Candor" | /usr/bin/grep -q "$architecture"
/usr/bin/codesign --verify --deep --strict "$verification_mount/Candor.app"
/usr/bin/hdiutil detach -quiet "$verification_mount"
is_verification_mounted=false

(
    cd "$artifacts_dir"
    /usr/bin/shasum -a 256 "${base_name}.zip" > "${base_name}.zip.sha256"
    /usr/bin/shasum -a 256 "${base_name}.dmg" > "${base_name}.dmg.sha256"
)

print -r -- "$dmg_path"
print -r -- "$zip_path"
