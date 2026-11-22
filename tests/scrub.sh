#!/usr/bin/env bash
# Fails when private data is in a file of this repo (tracked or new): home paths, LAN addresses,
# e-mail addresses (noreply is fine), em or en dashes, links that leave the repo. Machine and client names are private
# patterns, so they live outside the repo and are checked by omakit-scrub (sibling folder ../omakit, or on PATH).
# Usage: bash tests/scrub.sh
cd "$(dirname "$0")/.."
bad=0
files() { # files [extra pathspec]: repo files, minus this script
  git ls-files -z -co --exclude-standard -- . ':!tests/scrub.sh' ':!LICENSE' "$@"
}
check() { # check <label> <pathspec-exclude-or-.> <grep args>
  local label=$1 excl=$2; shift 2
  local hits
  hits=$(files "$excl" | xargs -0 grep -n -I "$@" -- 2>/dev/null | grep -v -E 'noreply@' | head -10 || true)
  if [ -n "$hits" ]; then echo "FOUND $label:"; echo "$hits"; bad=1; fi
}
check "a home path"            ':!tests/scrub.sh' -E "/home/[a-z]"
# branding/ is skipped here only: its brief points at the sister repos' branding folders.
check "a workspace link"       ':!branding' -E "\.\./\.\./\.\./|\.\./docs/|\.\./\.\./(omagnet|omahop|omadials|OmaBar)"
check "a LAN address"          ':!tests/scrub.sh' -E "192\.168\.[0-9]"
check "an e-mail address"      ':!tests/scrub.sh' -E "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}"
check "an em or en dash"       ':!tests/scrub.sh' -P "[\x{2013}\x{2014}]"
kit=../omakit/bin/omakit-scrub; [ -x "$kit" ] || kit=$(command -v omakit-scrub || true)
if [ -n "$kit" ]; then "$kit" . >/dev/null || { echo "FOUND a private pattern (run $kit . to see it)"; bad=1; }
else echo "omakit-scrub not found: private patterns not checked"; fi
if [ $bad = 0 ]; then echo "scrub ok"; else echo "scrub FAILED"; exit 1; fi
