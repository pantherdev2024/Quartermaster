#!/bin/bash
# The manifest is the one file two different readers must both accept: the
# shell's PluginRegistry, which decides whether the plugin loads at all, and
# the marketplace, which asks for two fields the registry does not.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/manifest.json"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

jq -e . "$MANIFEST" >/dev/null || fail "manifest is not valid JSON"

# services/PluginRegistry.qml validateManifest(): schemaVersion must be 1 and
# these five must be present, or the plugin is dropped with a console warning.
[[ $(jq -r '.schemaVersion' "$MANIFEST") == 1 ]] || fail "schemaVersion must be 1"
for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$MANIFEST" >/dev/null || fail "missing required field: $field"
done

# The publishing guide adds these two for the listing itself.
for field in author description; do
  jq -e --arg f "$field" '.[$f] | type == "string" and length > 0' "$MANIFEST" >/dev/null \
    || fail "marketplace requires a non-empty $field"
done

# The omarchy.* namespace is reserved; parseScanOutput() rejects a third-party
# plugin that claims it, and so does omarchy-plugin-validate.
id=$(jq -r '.id' "$MANIFEST")
[[ $id != omarchy.* ]] || fail "id claims the reserved omarchy.* namespace: $id"
[[ $id != */* && $id != *..* ]] || fail "id is not a single safe path segment: $id"

# A clone keeps omarchy.clonedFrom so removing it restores the built-in. A
# published plugin is not a clone of anything.
jq -e 'has("omarchy") and (.omarchy | has("clonedFrom")) | not' "$MANIFEST" >/dev/null \
  || fail "omarchy.clonedFrom is clone-only and must not ship"

# kinds and entryPoints have to agree, and every entry point has to be a safe
# relative path that exists — isSafeEntryPoint() plus the file on disk.
jq -e '.kinds | type == "array" and length > 0' "$MANIFEST" >/dev/null \
  || fail "kinds must be a non-empty array"
while read -r kind; do
  case "$kind" in
    bar-widget) key=barWidget ;;
    *) key="$kind" ;;
  esac
  entry=$(jq -r --arg k "$key" '.entryPoints[$k] // ""' "$MANIFEST")
  [[ -n $entry ]] || fail "kind '$kind' declares no entryPoints.$key"
  [[ ${entry:0:1} != "/" && $entry != *..* ]] || fail "unsafe entry point: $entry"
  [[ -f "$ROOT/$entry" ]] || fail "entry point file not found: $entry"
done < <(jq -r '.kinds[]' "$MANIFEST")

# A plugin directory may not contain symlinks.
found=$(find "$ROOT" -type l -not -path "$ROOT/.git/*" | head -1)
[[ -z $found ]] || fail "plugin directory contains a symlink: $found"

# What the marketplace and its neighbours expect beside the manifest.
for file in README.md LICENSE preview.png; do
  [[ -f "$ROOT/$file" ]] || fail "missing $file"
done

printf 'manifest-test: ok\n'
