#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="${HOUSTON_OUTPUT_DIR:-$ROOT/..}"
STAGE=$(mktemp -d /private/tmp/houston-dmg.XXXXXX)
ditto --norsrc "$OUT/Houston.app" "$STAGE/Houston.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/LICENSE" "$ROOT/THIRD-PARTY-NOTICES.md" "$ROOT/AI_DISCLOSURE.md" "$ROOT/SPARKLE-LICENSE.txt" "$STAGE/"
ditto -c -k --norsrc --keepParent "$ROOT" "$OUT/Houston-Source.zip"
cp "$OUT/Houston-Source.zip" "$STAGE/"
cat > "$STAGE/Install Houston.txt" <<'TEXT'
Drag Houston to Applications, then open it from Applications.
Requires Apple silicon and macOS 26 or later.
This development build is ad-hoc signed, not Developer ID notarized.
The complete corresponding source, GPL license, upstream credits and AI
usage disclosure are provided here and bundled in About Houston.
Updates are available from Settings > Updates, without an account or token.
TEXT
hdiutil create -volname Houston -srcfolder "$STAGE" -format UDZO -ov "$OUT/Houston.dmg"
hdiutil verify "$OUT/Houston.dmg"
shasum -a 256 "$OUT/Houston.dmg" "$OUT/Houston-Source.zip" > "$OUT/SHA256SUMS.txt"
print "Verified DMG: $OUT/Houston.dmg"
