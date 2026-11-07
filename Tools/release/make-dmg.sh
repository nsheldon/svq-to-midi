#!/bin/bash
# Builds the downloadable copy of SVQ to MIDI: Developer ID signed, notarized,
# stapled, in a DMG.
#
#   Tools/release/make-dmg.sh check          is this Mac ready (certificate, notary login)
#   Tools/release/make-dmg.sh [LABEL]        build build/release/SVQ to MIDI <version>[ LABEL].dmg
#                                            e.g. make-dmg.sh "beta 1"
#
# Needs, once:
#   - a "Developer ID Application" certificate in the Keychain (Xcode › Settings ›
#     Accounts › Manage Certificates › + › Developer ID Application);
#   - a notarytool login saved in the Keychain:
#       xcrun notarytool store-credentials "<profile name>" --apple-id <Apple ID> --team-id <team>
#     (with an app-specific password from account.apple.com), named by NOTARY_PROFILE.
# Optional: TEAM_ID picks the certificate when there are several.
# Nothing here holds a password. The working tree must be clean: a release is a commit.
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
root="$(cd "$(dirname "$0")/../.." && pwd)"
name="SVQ to MIDI"
profile="${NOTARY_PROFILE:-notary}"
out="$root/build/release"

identity() {
  security find-identity -v -p codesigning \
    | sed -n "s/.*\"\(Developer ID Application: .*(${TEAM_ID:-[A-Z0-9]*})\)\"/\1/p" | head -1
}

check() {
  local ok=0 id
  id="$(identity)"
  if [ -n "$id" ]; then echo "certificate    $id"
  else echo "certificate    MISSING: no Developer ID Application identity${TEAM_ID:+ for team $TEAM_ID}"; ok=1; fi
  if xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "notary login   \"$profile\""
  else echo "notary login   MISSING or refused: \"$profile\" (set NOTARY_PROFILE)"; ok=1; fi
  return $ok
}

# Submits a file and waits; on anything but Accepted, prints Apple's log.
notarize() {
  local result id status
  echo "Notarizing $(basename "$1")…"
  result="$(xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --output-format plist)"
  id="$(/usr/libexec/PlistBuddy -c 'Print :id' /dev/stdin <<< "$result")"
  status="$(/usr/libexec/PlistBuddy -c 'Print :status' /dev/stdin <<< "$result")"
  if [ "$status" != "Accepted" ]; then
    echo "Notarization: $status ($id)" >&2
    xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true
    exit 1
  fi
  echo "  accepted ($id)"
}

if [ "${1:-}" = check ]; then check; exit; fi
label="${1:-}"
check >/dev/null || { check; exit 1; }
if [ -n "$(git -C "$root" status --porcelain)" ]; then
  echo "The working tree has changes. Commit them first: a release is a commit." >&2
  exit 1
fi
id="$(identity)"
team="$(sed -n 's/.*(\([A-Z0-9]*\))$/\1/p' <<< "$id")"
work="$(mktemp -d)"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Xcode registers the app it builds with Launch Services; unregister the temporary copy before
# deleting it, or macOS may later try to open the deleted copy ("its executable is missing").
trap '"$lsregister" -u "$work/dd/Build/Products/Release/$name.app" 2>/dev/null; rm -rf "$work"' EXIT

echo "Building $(git -C "$root" rev-parse --short HEAD) signed as ${id}…"
xcodebuild -quiet -project "$root/$name.xcodeproj" -scheme "$name" -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$work/dd" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$id" DEVELOPMENT_TEAM="$team" \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp build
app="$work/dd/Build/Products/Release/$name.app"
plist="$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"

# What notarization would refuse, said before the wait rather than after it.
codesign --verify --deep --strict "$app"
details="$(codesign -dvv "$app" 2>&1)"
grep -q "Authority=Developer ID Application" <<< "$details" || { echo "Not signed with Developer ID." >&2; exit 1; }
grep -q "flags=.*runtime" <<< "$details" || { echo "No hardened runtime." >&2; exit 1; }
entitlements="$(codesign -d --entitlements :- "$app" 2>/dev/null)"
grep -q "com.apple.security.app-sandbox" <<< "$entitlements" || { echo "Not sandboxed." >&2; exit 1; }
! grep -q "get-task-allow" <<< "$entitlements" || { echo "Has get-task-allow (a debug signature)." >&2; exit 1; }

# The app first, so a copy dragged out of the DMG carries its own ticket.
ditto -c -k --keepParent "$app" "$work/app.zip"
notarize "$work/app.zip"
xcrun stapler staple -q "$app"

# A DMG holding the app, the license and a link to Applications to drag it onto.
mkdir -p "$work/dmg" "$out"
ditto "$app" "$work/dmg/$name.app"
cp "$root/LICENSE" "$work/dmg/License.txt"
ln -s /Applications "$work/dmg/Applications"
dmg="$out/$name $version${label:+ $label}.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "$name" -srcfolder "$work/dmg" -fs HFS+ -format UDZO "$dmg"
codesign --sign "$id" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple -q "$dmg"

# As Gatekeeper will see them.
spctl --assess --type open --context context:primary-signature "$dmg"
mnt="$(hdiutil attach -nobrowse -readonly "$dmg" | sed -n 's|.*\(/Volumes/.*\)|\1|p' | tail -1)"
spctl --assess --type execute "$mnt/$name.app"
xcrun stapler validate -q "$mnt/$name.app"
hdiutil detach -quiet "$mnt"

echo "Built $name $version ($build)${label:+ $label}"
echo "  $dmg"
echo "  $(du -h "$dmg" | cut -f1 | tr -d ' '), SHA-256 $(shasum -a 256 "$dmg" | cut -d' ' -f1)"
