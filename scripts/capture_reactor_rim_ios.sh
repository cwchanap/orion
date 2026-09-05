#!/usr/bin/env bash
set -euo pipefail
out="$1"
mkdir -p "$(dirname "$out")"
xcrun simctl io booted screenshot "$out"
