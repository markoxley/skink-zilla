#!/bin/sh
# install_local.sh — install this module into a local scales mirror and
# smoke-test that a consumer project can `scales add` + compile + run it.
#
# Usage:  ./install_local.sh [mirror_root]
#
# mirror_root defaults to $HOME/.local/skink/mirror. The script copies
# the package into <mirror>/markoxley/<repo>/<version>/, creates a
# scratch project, runs `scales add`/`scales install` against
# SCALES_GITHUB_MIRROR, and compiles a program that imports the module.
set -eu

REPO=$(basename "$(pwd)")          # e.g. skink-dbx
VERSION=$(sed -n 's/^version *= *"\(.*\)".*/\1/p' skink.toml | head -1)
MODNAME=$(sed -n 's/^name *= *"\(.*\)".*/\1/p' skink.toml | head -1)
MIRROR="${1:-$HOME/.local/skink/mirror}"

[ -n "$VERSION" ] || { echo "no version in skink.toml"; exit 1; }
[ -n "$MODNAME" ] || { echo "no package name in skink.toml"; exit 1; }

DEST="$MIRROR/markoxley/$REPO/$VERSION"
mkdir -p "$DEST"
# Package contents = everything except VCS/build artifacts.
for f in *; do
    case "$f" in
        .git|__skink_*|*.o|*.ll) continue ;;
    esac
    cp -r "$f" "$DEST/" 2>/dev/null || true
done
echo "mirrored $REPO@$VERSION -> $DEST"

# During local development the global scales cache is refreshed in place
# so sibling modules pick up source edits without a version bump.
CACHE="$HOME/.local/skink/scales/packages/markoxley/$REPO/$VERSION"
if [ -d "$CACHE" ]; then
    rm -rf "$CACHE"
    mkdir -p "$CACHE"
    for f in *; do
        case "$f" in
            .git|__skink_*|*.o|*.ll) continue ;;
        esac
        cp -r "$f" "$CACHE/" 2>/dev/null || true
    done
    echo "refreshed cache -> $CACHE"
fi

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
cd "$SCRATCH"

cat > skink.toml <<EOF
[package]
name = "probe"
version = "0.1.0"
entry = "main.skink"

[target]
env = "std"

[dependencies]
EOF

cat > main.skink <<EOF
module main

import "mod/markoxley/$REPO"

fn main() -> int {
    println("$MODNAME installed and importable")
    return 0
}
EOF

export SCALES_GITHUB_MIRROR="$MIRROR"
scales add "mod/markoxley/$REPO@$VERSION"
scales install
skink -o probe main.skink
./probe
echo "install smoke test OK: $REPO@$VERSION"
