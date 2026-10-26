#!/usr/bin/env bash
# Build a release zip of the CrewSwap mod.
#
#   tools/package.sh <version> [build-suffix]
#
#   tools/package.sh 0.9.0          -> BUILD = 0.9.0
#   tools/package.sh 0.9.0 beta     -> BUILD = 0.9.0-beta
#   tools/package.sh 0.9.0 -beta    -> BUILD = 0.9.0-beta
#   tools/package.sh 1.0.0 rc-1     -> BUILD = 1.0.0-rc-1   (the release workflow passes a tag's
#                                      suffix through as-is, so v1.0.0-rc-1 works)
#
# Stamps MODVERSION/BUILD into Lua/crewswap/shared/build.lua and modversion into filelist.xml
# of a staged copy (the working tree is never modified), then writes
# dist/CrewSwap-<version>.zip with a single top-level CrewSwap/ folder and prints its path.
#
# Server and clients compare BUILD when they say hello, so everyone must run a copy made
# from the same package (the Workshop upload should be the contents of this zip).
set -euo pipefail

usage() { echo "usage: tools/package.sh <version> [build-suffix]   e.g. tools/package.sh 0.9.0 beta" >&2; exit 2; }

[[ $# -ge 1 && $# -le 2 ]] || usage
VERSION="$1"
SUFFIX="${2:-}"

# modversion is shown by the game and must not contain ';' or '=' (Workshop metadata separators).
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "error: version must look like 0.9.0, got '$VERSION'" >&2; exit 2; }
SUFFIX="${SUFFIX#-}"
if [[ -n "$SUFFIX" ]]; then
  [[ "$SUFFIX" =~ ^[0-9A-Za-z][0-9A-Za-z.-]*$ ]] || { echo "error: build suffix may only contain letters, digits, dots and hyphens (and must start with a letter or digit), got '$SUFFIX'" >&2; exit 2; }
  BUILD="$VERSION-$SUFFIX"
else
  BUILD="$VERSION"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/mod/CrewSwap"
DIST="$ROOT/dist"
ZIP="$DIST/CrewSwap-$VERSION.zip"

[[ -f "$SRC/filelist.xml" && -f "$SRC/Lua/crewswap/shared/build.lua" ]] || { echo "error: $SRC does not look like the CrewSwap mod" >&2; exit 1; }
command -v zip >/dev/null || { echo "error: 'zip' is not installed" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/CrewSwap"
cp -R "$SRC" "$STAGE"
# Drop editor/OS clutter that should never ship.
find "$STAGE" \( -name '.DS_Store' -o -name '*.tmp' -o -name '*~' -o -name '*.swp' \) -type f -delete

BUILD_LUA="$STAGE/Lua/crewswap/shared/build.lua"
FILELIST="$STAGE/filelist.xml"
sed -i.bak "s/BUILD = '[^']*'/BUILD = '$BUILD'/; s/MODVERSION = '[^']*'/MODVERSION = '$VERSION'/" "$BUILD_LUA"
sed -i.bak "s/modversion=\"[^\"]*\"/modversion=\"$VERSION\"/" "$FILELIST"
rm -f "$BUILD_LUA.bak" "$FILELIST.bak"

grep -q "BUILD = '$BUILD'" "$BUILD_LUA" || { echo "error: could not stamp BUILD in build.lua" >&2; exit 1; }
grep -q "MODVERSION = '$VERSION'" "$BUILD_LUA" || { echo "error: could not stamp MODVERSION in build.lua" >&2; exit 1; }
grep -q "modversion=\"$VERSION\"" "$FILELIST" || { echo "error: could not stamp modversion in filelist.xml" >&2; exit 1; }

mkdir -p "$DIST"
rm -f "$ZIP"
(cd "$TMP" && zip -qrX "$ZIP" CrewSwap)

echo "built CrewSwap $VERSION (BUILD $BUILD)" >&2
echo "$ZIP"
