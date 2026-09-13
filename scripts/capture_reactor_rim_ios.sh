#!/usr/bin/env bash
set -euo pipefail
out="$1"
mkdir -p "$(dirname "$out")"
xcrun simctl io booted screenshot "$out"
# `booted` accepts whichever simulator happens to be running, so validate the
# capture against the evidence contract (390x844 product portrait) before the
# row is recorded: pixel dims must equal 390x844 at the device's native scale.
w=$(sips -g pixelWidth "$out" | awk '/pixelWidth/ {print $2}')
h=$(sips -g pixelHeight "$out" | awk '/pixelHeight/ {print $2}')
case "${w}x${h}" in
  390x844|780x1688|1170x2532) ;;
  *)
    rm -f "$out"
    echo "live evidence requires a 390x844 portrait capture, got ${w}x${h}px" >&2
    exit 1
    ;;
esac
