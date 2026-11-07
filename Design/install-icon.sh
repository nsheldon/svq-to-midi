#!/bin/bash
# Installs one of the icon concepts as the app icon and About window art.
#
#   Design/install-icon.sh Platinum          # or "Neon Grid", Memphis, "Dot Matrix"
#
# To change the artwork itself, edit Design/IconArt.swift and regenerate the concepts first:
#
#   swiftc -O Design/IconArt.swift -o /tmp/iconart && /tmp/iconart "Design/Icon Concepts"
#
# (Prefix with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer if needed.)
set -euo pipefail

cd "$(dirname "$0")/.."
theme="${1:?Usage: Design/install-icon.sh <Platinum | Neon Grid | Memphis | Dot Matrix>}"
src="Design/Icon Concepts/$theme"
assets="SVQ to MIDI/Assets.xcassets"

[ -d "$src" ] || { echo "No concept named \"$theme\" in Design/Icon Concepts" >&2; exit 1; }

# The app icon is an Icon Composer file (macOS 26 renders it natively, with its dark and tinted
# styles; Xcode derives the icons for macOS 13-15 from it).
rm -rf "SVQ to MIDI/AppIcon.icon"
cp -R "$src/AppIcon.icon" "SVQ to MIDI/AppIcon.icon"

mkdir -p "$assets/AboutArt.imageset"
cp "$src/about@2x.png" "$assets/AboutArt.imageset/about@2x.png"
sips -Z 560 "$src/about@2x.png" --out "$assets/AboutArt.imageset/about.png" >/dev/null
cat > "$assets/AboutArt.imageset/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "about.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "about@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
echo "$theme" > "$assets/AboutArt.imageset/.theme"
echo "Installed \"$theme\". Rebuild the app to see it."
