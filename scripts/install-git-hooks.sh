#!/usr/bin/env sh
set -eu

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit

printf 'Installed Git hooks from %s/.githooks\n' "$repo_root"
printf 'Pre-commit checks Dart formatting and runs flutter analyze.\n'

