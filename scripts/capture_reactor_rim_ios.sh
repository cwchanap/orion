#!/usr/bin/env bash
set -euo pipefail
out="$1"
mkdir -p "$(dirname "$out")"

# `booted` accepts whichever simulator happens to be running, and the evidence
# contract is a 390x844 product-portrait *logical viewport*. Pixel size alone
# cannot prove that — a 393x852-point iPhone (16/17-class) normalizes to the
# same PNG size while Flutter laid the scene out at a different viewport.
# Resolve the booted device's type profile and read its declared screen
# geometry: logical points = mainScreen{Width,Height} / mainScreenScale.
dtype=$(
  xcrun simctl list devices booted -j |
    sed -n 's/.*"deviceTypeIdentifier" : "\([^"]*\)".*/\1/p' |
    head -1
)
if [ -z "$dtype" ]; then
  rm -f "$out"
  echo "no booted iOS simulator to capture" >&2
  exit 1
fi
bundle=$(
  xcrun simctl list devicetypes -j | awk -v id="$dtype" '
    match($0, /"bundlePath" : "[^"]+"/) {
      bp = substr($0, RSTART + 16, RLENGTH - 17)
      gsub(/\\\//, "/", bp)
    }
    match($0, /"identifier" : "[^"]+"/) {
      if (substr($0, RSTART + 16, RLENGTH - 17) == id) { print bp; exit }
    }
  '
)
profile="$bundle/Contents/Resources/profile.plist"
if [ -z "$bundle" ] || [ ! -f "$profile" ]; then
  rm -f "$out"
  echo "cannot resolve the screen profile for $dtype" >&2
  exit 1
fi
sw=$(plutil -extract mainScreenWidth raw -o - "$profile")
sh=$(plutil -extract mainScreenHeight raw -o - "$profile")
ss=$(plutil -extract mainScreenScale raw -o - "$profile")
lw=$(awk -v p="$sw" -v s="$ss" 'BEGIN { printf "%d", p / s }')
lh=$(awk -v p="$sh" -v s="$ss" 'BEGIN { printf "%d", p / s }')
if [ "$lw" != 390 ] || [ "$lh" != 844 ]; then
  rm -f "$out"
  echo "live evidence requires a 390x844 logical viewport; $dtype renders at ${lw}x${lh}pt — boot a 390x844 model (iPhone 14-class or iPhone 16e)" >&2
  exit 1
fi

raw="$(mktemp -t reactor-rim-capture)"
trap 'rm -f "$raw"' EXIT
xcrun simctl io booted screenshot "$raw"
# The capture must be the device's native portrait panel — a rotated or
# degenerate shot is refused — then native pixels normalize to the contract
# size (every 390x844-point iPhone shoots 1170x2532 @3x).
w=$(sips -g pixelWidth "$raw" | awk '/pixelWidth/ {print $2}')
h=$(sips -g pixelHeight "$raw" | awk '/pixelHeight/ {print $2}')
if [ "$w" != "$sw" ] || [ "$h" != "$sh" ]; then
  rm -f "$out"
  echo "live evidence requires the native portrait panel, got ${w}x${h}px for a ${sw}x${sh}px device" >&2
  exit 1
fi
if [ "$w" != 390 ] || [ "$h" != 844 ]; then
  echo "normalized ${w}x${h}px capture to 390x844" >&2
fi
sips -z 844 390 "$raw" --out "$out" >/dev/null
