#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?Usage: scripts/ci_build.sh android|macos|windows}"
case "$TARGET" in
  android|macos|windows) ;;
  *) echo "Unsupported target: $TARGET" >&2; exit 1 ;;
esac

# GitHub-only settings. These are intentionally separate from build.sh's
# local true/false settings.
export BUILD_TARGET="$TARGET"
export BUILD_SINGLE_TARGET=true

exec ./scripts/build.sh "$TARGET"
