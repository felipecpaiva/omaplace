#!/usr/bin/env bash
# Fails when private data is in a file of this repo (tracked or new): home paths, LAN addresses,
# machine names, a client name, e-mail addresses (noreply is fine), em or en dashes.
# docs/research/ is private history: it is skipped for the home path and machine name checks only.
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
check "a home path"            ':!docs/research' -E "/home/[a-z]"
check "a private machine name" ':!docs/research' -E "(Z13P|X1C|pi5paiva|MbpM5Max|iFelipeM2Max|DESKTOP-)"
check "a LAN address"          ':!tests/scrub.sh' -E "192\.168\.[0-9]"
check "an e-mail address"      ':!tests/scrub.sh' -E "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}"
check "a client name"          ':!tests/scrub.sh' -i -E "tribalscale"
check "an em or en dash"       ':!tests/scrub.sh' -P "[\x{2013}\x{2014}]"
if [ $bad = 0 ]; then echo "scrub ok"; else echo "scrub FAILED"; exit 1; fi
