#!/usr/bin/env bash
set -euo pipefail
out="$1"
mkdir -p "$(dirname "$out")"
raw="$(mktemp -t reactor-rim-capture)"
trap 'rm -f "$raw"' EXIT
xcrun simctl io booted screenshot "$raw"
# `booted` accepts whichever simulator happens to be running. The evidence
# contract is a 390x844 product-portrait capture, so refuse anything that is
# not a portrait iPhone shot (landscape, iPad, or a degenerate capture), then
# normalize the native pixels to the contract size — every 19.5:9 iPhone
# viewport shares the ~0.46 aspect, so a different booted model still yields
# valid evidence instead of failing before normalization can run.
w=$(sips -g pixelWidth "$raw" | awk '/pixelWidth/ {print $2}')
h=$(sips -g pixelHeight "$raw" | awk '/pixelHeight/ {print $2}')
if ! awk -v w="$w" -v h="$h" \
  'BEGIN { exit !(h > w && h >= 1000 && w / h > 0.44 && w / h < 0.48) }'; then
  rm -f "$out"
  echo "live evidence requires a portrait iPhone capture, got ${w}x${h}px" >&2
  exit 1
fi
if [ "$w" != 390 ] || [ "$h" != 844 ]; then
  echo "normalized ${w}x${h}px capture to 390x844" >&2
fi
sips -z 844 390 "$raw" --out "$out" >/dev/null
