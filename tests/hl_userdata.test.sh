#!/usr/bin/env bash
# Hyprland passes windows, monitors and workspaces to Lua as userdata, while the fake hl in the tests uses tables.
# A `type(x) == "table"` test on such an object passes every unit test and silently ignores everything live
# (found in the 2026-11-21 live run). This check fails on that pattern for the usual hl object names.
set -euo pipefail
cd "$(dirname "$0")/.."
pattern='type\((w|win|window|mon|monitor|ws|workspace)\) *[~=]= *"table"'
if grep -nE "$pattern" lua/*.lua | grep -v -- "-- plain table"; then
  echo "FAIL: an hl object is checked with type(...) == \"table\"; Hyprland objects are userdata"
  exit 1
fi
echo "hl userdata check ok"
