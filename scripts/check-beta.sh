#!/bin/zsh
# Checks an exported beta before it goes to testers — the things that made beta 1.2 (2)/(3)
# refuse to launch on a tester's Mac or open an empty library.
#
#   scripts/check-beta.sh <new booklist.app> [<previous booklist.app>]
#
# Exits non-zero on any problem. With a previous build, it also compares the two: anything that
# changes where macOS keeps the app's data (bundle ID, signing team, entitlements) is an error
# unless it's deliberate and the upgrade has been rehearsed (see CLAUDE.md › Releasing a beta).

NEW="$1"; OLD="$2"
[ -d "$NEW" ] || { echo "usage: $0 <new booklist.app> [<previous booklist.app>]"; exit 2; }
problems=0
fail() { echo "  ✘ $1"; problems=$((problems + 1)); }
ok()   { echo "  ✔ $1"; }

info() { plutil -extract "$2" raw -o - "$1/Contents/Info.plist" 2>/dev/null; }
entitlement_keys() {
  codesign -d --entitlements - --xml "$1" 2>/dev/null | plutil -convert json -o - - 2>/dev/null \
    | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin).keys())))' 2>/dev/null
}
team() { codesign -dvv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'; }

echo "booklist $(info "$NEW" CFBundleShortVersionString) ($(info "$NEW" CFBundleVersion)) — $NEW"

# 1. Signature
codesign --verify --deep --strict "$NEW" 2>/dev/null && ok "signature valid (app + extension)" || fail "signature invalid"

# 2. No provisioning profile: free-account profiles only list the developer's own Mac.
profiles=$(find "$NEW" -name embedded.provisionprofile | wc -l | tr -d ' ')
[ "$profiles" = 0 ] && ok "no provisioning profile embedded" || fail "$profiles provisioning profile(s) embedded — the build won't launch on testers' Macs"

# 3. Only entitlements that work without a profile.
allowed="com.apple.security.app-sandbox com.apple.security.network.client com.apple.security.files.user-selected.read-write com.apple.security.files.user-selected.read-only com.apple.security.files.bookmarks.app-scope"
for bundle in "$NEW" "$NEW/Contents/PlugIns/booklist share.appex"; do
  for key in $(entitlement_keys "$bundle"); do
    [[ " $allowed " == *" $key "* ]] || fail "$(basename "$bundle"): entitlement $key isn't on the allowed list"
  done
done
[ $problems = 0 ] && ok "entitlements: only sandbox, network and file access"

# 4. App and share extension carry the same version.
ext="$NEW/Contents/PlugIns/booklist share.appex"
[ "$(info "$NEW" CFBundleVersion)" = "$(info "$ext" CFBundleVersion)" ] && [ "$(info "$NEW" CFBundleShortVersionString)" = "$(info "$ext" CFBundleShortVersionString)" ] \
  && ok "app and extension versions match" || fail "app and share extension versions differ"

# 5. Release build: no debug-only stress tooling.
strings "$NEW/Contents/MacOS/booklist" | grep -q "booklist-stress-images" && fail "debug-only stress code is in the build" || ok "no debug-only code"

# 6. Compared with the previous beta: nothing that moves or locks away the user's data.
if [ -n "$OLD" ]; then
  echo "compared with $(info "$OLD" CFBundleShortVersionString) ($(info "$OLD" CFBundleVersion)):"
  [ "$(info "$NEW" CFBundleIdentifier)" = "$(info "$OLD" CFBundleIdentifier)" ] && ok "same bundle ID" || fail "bundle ID changed — the app gets a new, empty container"
  [ "$(team "$NEW")" = "$(team "$OLD")" ] && ok "same signing team" || fail "signing team changed — macOS may refuse the old container"
  added=$(comm -13 <(entitlement_keys "$OLD") <(entitlement_keys "$NEW") | tr '\n' ' ')
  removed=$(comm -23 <(entitlement_keys "$OLD") <(entitlement_keys "$NEW") | tr '\n' ' ')
  [ -z "$added$removed" ] && ok "same entitlements" || fail "entitlements changed (added: ${added:-none}; removed: ${removed:-none}) — rehearse the upgrade before sending"
  if [ "$(info "$NEW" CFBundleShortVersionString).$(info "$NEW" CFBundleVersion)" = "$(info "$OLD" CFBundleShortVersionString).$(info "$OLD" CFBundleVersion)" ]; then
    fail "same version and build number as the previous beta"
  fi
fi

echo
[ $problems = 0 ] && echo "OK to send." || echo "$problems problem(s) — don't send this build yet."
exit $problems
