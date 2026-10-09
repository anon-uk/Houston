#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
SDK="${HOUSTON_SPARKLE_DIR:-$ROOT/../../work/Sparkle}"
mkdir -p "$SDK"
ARCHIVE="$SDK/Sparkle.tar.xz"
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 'https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz' -o "$ARCHIVE"
fi
print 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  '"$ARCHIVE" | shasum -a 256 --check
if [[ ! -d "$SDK/Sparkle.framework" ]]; then tar -xf "$ARCHIVE" -C "$SDK"; fi
