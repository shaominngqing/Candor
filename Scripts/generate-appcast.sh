#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
architecture="${1:-$(uname -m)}"
release_tag="${2:-}"
private_key_file="${3:-}"
artifacts_dir="${4:-"$project_root/artifacts"}"
account="io.github.shaominngqing.candor"
repository="shaominngqing/Candor"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$project_root/AppResources/Info.plist")
base_name="Candor-${version}-macOS-${architecture}"
archive_path="$artifacts_dir/${base_name}.zip"
feed_name="appcast-${architecture}.xml"
feed_path="$artifacts_dir/$feed_name"
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/candor-appcast.XXXXXX")

cleanup() {
    /bin/rm -rf "$work_dir"
}
trap cleanup EXIT

case "$architecture" in
    arm64 | x86_64) ;;
    *)
        echo "Unsupported architecture: $architecture" >&2
        exit 64
        ;;
esac

if [[ -z "$release_tag" ]]; then
    echo "A release tag such as v${version} is required" >&2
    exit 64
fi
if [[ "$release_tag" != "v${version}" ]]; then
    echo "Release tag $release_tag does not match app version $version" >&2
    exit 65
fi

if [[ ! -f "$archive_path" ]]; then
    echo "Missing update archive: $archive_path" >&2
    exit 66
fi

generate_appcast=$(find "$project_root/.build/artifacts" -type f -name generate_appcast -print -quit)
if [[ -z "$generate_appcast" ]]; then
    echo "Sparkle generate_appcast tool was not resolved" >&2
    exit 66
fi

/bin/cp "$archive_path" "$work_dir/$base_name.zip"

generate_options=(
    --account "$account"
    --disable-signing-warning
    --download-url-prefix "https://github.com/${repository}/releases/download/${release_tag}/"
    --full-release-notes-url "https://github.com/${repository}/releases/tag/${release_tag}"
    --link "https://github.com/${repository}"
    --maximum-deltas 0
    --maximum-versions 1
    -o "$feed_name"
)
if [[ -n "$private_key_file" ]]; then
    generate_options+=(--ed-key-file "$private_key_file")
fi

(
    cd "$work_dir"
    "$generate_appcast" "${generate_options[@]}" "$work_dir"
)

/usr/bin/xmllint --noout "$work_dir/$feed_name"
/usr/bin/grep -q "sparkle:edSignature=" "$work_dir/$feed_name"
/usr/bin/grep -q "sparkle-signatures:" "$work_dir/$feed_name"
/usr/bin/grep -q "<sparkle:shortVersionString>${version}</sparkle:shortVersionString>" "$work_dir/$feed_name"
/usr/bin/grep -q "releases/download/${release_tag}/${base_name}.zip" "$work_dir/$feed_name"
/bin/cp "$work_dir/$feed_name" "$feed_path"

print -r -- "$feed_path"
