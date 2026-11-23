#!/usr/bin/env bash
# libexec/install-app and `omaplace install-app`: a wrong sha256 or a failed download installs nothing and never runs
# sudo or pacman. curl, sudo and pacman are fakes that log their calls; nothing real is downloaded or installed.
# Usage: bash tests/install_app.test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir "$tmp/bin"
export FAKE_LOG="$tmp/calls"

# curl writes FAKE_BODY to the -o file (or fails when FAKE_CURL_FAIL is set), and logs the url (last argument).
cat > "$tmp/bin/curl" <<'FAKE'
#!/usr/bin/env bash
echo "curl ${*: -1}" >> "$FAKE_LOG"
[ -z "${FAKE_CURL_FAIL:-}" ] || exit 22
while [ $# -gt 0 ]; do [ "$1" = -o ] && { printf '%s' "$FAKE_BODY" > "$2"; break; }; shift; done
FAKE
for priv in sudo pacman; do printf '#!/usr/bin/env bash\necho "%s $*" >> "$FAKE_LOG"\n' "$priv" > "$tmp/bin/$priv"; done
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"

fail=0
check() { if [ "$2" = 1 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi }
has() { case $1 in *"$2"*) echo 1 ;; *) echo 0 ;; esac }
no_priv() { if grep -qE '^(sudo|pacman) ' "$FAKE_LOG" 2>/dev/null; then echo 0; else echo 1; fi }

# The real pin, the real bin/omaplace: a package with the wrong bytes is refused.
: > "$FAKE_LOG"
set +e
out=$(FAKE_BODY="not the reviewed package" bin/omaplace install-app 2>&1); code=$?
set -e
check "wrong digest exits 5" "$([ "$code" = 5 ] && echo 1 || echo 0)"
check "wrong digest says nothing installed" "$(has "$out" "does not match the pinned sha256")"
check "wrong digest never runs sudo or pacman" "$(no_priv)"
check "the url is the pinned tag, not latest" "$(has "$(cat "$FAKE_LOG")" "/releases/download/$(sed -n 's/^TAG=//p' app/PINNED)/")"

# A failed download installs nothing either.
: > "$FAKE_LOG"
set +e
out=$(FAKE_CURL_FAIL=1 bin/omaplace install-app 2>&1); code=$?
set -e
check "failed download exits 5" "$([ "$code" = 5 ] && echo 1 || echo 0)"
check "failed download never runs sudo or pacman" "$(no_priv)"

# A tree whose pin matches the downloaded bytes does install, through sudo pacman -U on the checked file.
mkdir -p "$tmp/tree/app" "$tmp/tree/libexec"
cp libexec/install-app "$tmp/tree/libexec/"
body="the pinned package"
printf 'TAG=v9.9.9\nFILE=omaplace-settings-9.9.9-1-x86_64.pkg.tar.zst\nSHA256=%s\n' "$(printf '%s' "$body" | sha256sum | cut -d' ' -f1)" > "$tmp/tree/app/PINNED"
: > "$FAKE_LOG"
FAKE_BODY=$body bash "$tmp/tree/libexec/install-app" > /dev/null
check "matching digest installs with sudo pacman -U" "$(has "$(cat "$FAKE_LOG")" "sudo pacman -U ")"

# A pin that is not a sha256 is refused before any download.
sed -i 's/^SHA256=.*/SHA256=latest/' "$tmp/tree/app/PINNED"
: > "$FAKE_LOG"
set +e; bash "$tmp/tree/libexec/install-app" > /dev/null 2>&1; code=$?; set -e
check "a bad pin file exits 5 without a download" "$([ "$code" = 5 ] && [ ! -s "$FAKE_LOG" ] && echo 1 || echo 0)"

[ "$fail" = 0 ] && echo "install_app tests ok"
exit "$fail"
