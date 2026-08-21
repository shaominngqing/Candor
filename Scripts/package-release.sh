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
mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/candor-mount.XXXXXX")
is_mounted=false

cleanup() {
    if [[ "$is_mounted" == true ]]; then
        /usr/bin/hdiutil detach -quiet "$mount_dir" || true
    fi
    /bin/rm -rf "$staging_dir" "$mount_dir"
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
/usr/bin/file "$executable" | /usr/bin/grep -q "$architecture"
/usr/bin/codesign --verify --deep --strict "$app_bundle"

mkdir -p "$artifacts_dir"
/bin/rm -f "$zip_path" "$zip_path.sha256" "$dmg_path" "$dmg_path.sha256"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$zip_path"

/usr/bin/ditto "$app_bundle" "$staging_dir/Candor.app"
/bin/ln -s /Applications "$staging_dir/Applications"
/usr/bin/touch "$staging_dir/.metadata_never_index"
/usr/bin/hdiutil create \
    -quiet \
    -volname "Candor $version" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

if [[ "$codesign_identity" != "-" ]]; then
    /usr/bin/codesign --force --sign "$codesign_identity" --timestamp "$dmg_path"
    /usr/bin/codesign --verify --verbose=2 "$dmg_path"
fi

/usr/bin/hdiutil verify -quiet "$dmg_path"
is_mounted=true
/usr/bin/hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_dir" "$dmg_path"
guard_file "$mount_dir/Candor.app"
guard_file "$mount_dir/Applications"
[[ "$(/usr/bin/readlink "$mount_dir/Applications")" == "/Applications" ]]
/usr/bin/file "$mount_dir/Candor.app/Contents/MacOS/Candor" | /usr/bin/grep -q "$architecture"
/usr/bin/codesign --verify --deep --strict "$mount_dir/Candor.app"
/usr/bin/hdiutil detach -quiet "$mount_dir"
is_mounted=false

(
    cd "$artifacts_dir"
    /usr/bin/shasum -a 256 "${base_name}.zip" > "${base_name}.zip.sha256"
    /usr/bin/shasum -a 256 "${base_name}.dmg" > "${base_name}.dmg.sha256"
)

print -r -- "$dmg_path"
print -r -- "$zip_path"
