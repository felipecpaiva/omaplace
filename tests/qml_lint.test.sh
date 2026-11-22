#!/usr/bin/env bash
# qmllint with the shell's own modules on the import path, so a wrong property or signal on a qs.Ui type is caught.
# qmllint exits 0 on warnings, so this script fails on the kinds that mean a real mistake. Style and Color tokens are
# typed QObject in the shell, so their member lookups ("not found on type QObject") are left out as noise, and so is
# "PanelWindow is not creatable" (Quickshell registers it that way; omagnet's shipped panel gets the same).
# Usage: bash tests/qml_lint.test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
lint=/usr/lib/qt6/bin/qmllint
shell_dir=/usr/share/omarchy/shell
if [ ! -x "$lint" ] || [ ! -d "$shell_dir/Ui" ]; then echo "SKIP qmllint or the Omarchy shell not installed"; exit 0; fi
imports=$(mktemp -d)
trap 'rm -f "$imports/qs"; rmdir "$imports"' EXIT
ln -s "$shell_dir" "$imports/qs"
shopt -s nullglob
files=(*.qml)
out=$("$lint" -I "$imports" "${files[@]}" 2>&1 || true)
bad=$(printf '%s\n' "$out" | grep -E '^(Error|Warning):' \
  | grep -v -E 'not found on type "QObject"|\[unqualified\]|Unused import|Type PanelWindow is not creatable' || true)
if [ -n "$bad" ]; then printf '%s\n' "$bad"; exit 1; fi
echo "qml lint ok (${#files[@]} files)"
