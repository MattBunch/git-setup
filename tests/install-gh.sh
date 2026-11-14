#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" GH_INSTALL_OS_RELEASE="$WORK/os-release" MOCK_LOG="$WORK/log" MOCK_BIN="$WORK/bin"
mkdir -p "$HOME" "$MOCK_BIN"
# Use a controlled PATH so no real package manager, sudo, or gh can run.
for tool in bash dirname pwd git cmp awk mktemp rm mkdir cat cp chmod mv ln readlink date sed tr head find wc; do
    path=$(command -v "$tool")
    ln -s "$path" "$MOCK_BIN/$tool"
done
export PATH="$MOCK_BIN"
cat > "$MOCK_BIN/sudo" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG"
[[ ${MOCK_FAIL:-0} != 1 ]] || exit 1
if [[ $* == 'apt-get install gh' || $* == 'dnf install gh' ]]; then
    printf '#!/usr/bin/env bash\necho gh version mock\n' > "$MOCK_BIN/gh"
    chmod +x "$MOCK_BIN/gh"
fi
MOCK
cat > "$MOCK_BIN/dnf" <<'MOCK'
#!/usr/bin/env bash
echo "${MOCK_DNF_VERSION:-dnf5 version 5.2.17.0}"
MOCK
cat > "$MOCK_BIN/apt-get" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat > "$MOCK_BIN/dpkg" <<'MOCK'
#!/usr/bin/env bash
echo amd64
MOCK
cat > "$MOCK_BIN/wget" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$MOCK_BIN/sudo" "$MOCK_BIN/dnf" "$MOCK_BIN/apt-get" "$MOCK_BIN/dpkg" "$MOCK_BIN/wget"
fail() { echo "FAIL: $*" >&2; exit 1; }
printf 'ID=fedora\n' > "$GH_INSTALL_OS_RELEASE"
"$ROOT/install.sh" >/dev/null
[[ ! -e $MOCK_LOG ]] || fail 'default invoked sudo'
if printf 'n\n' | "$ROOT/install.sh" --with-gh >/dev/null 2>&1; then fail 'decline accepted'; fi
[[ ! -e $MOCK_LOG ]] || fail 'decline invoked sudo'
if printf 'y\n' | MOCK_FAIL=1 "$ROOT/install.sh" --with-gh >/dev/null 2>&1; then fail 'package failure accepted'; fi
printf 'y\n' | "$ROOT/install.sh" --with-gh >/dev/null
[[ -x $MOCK_BIN/gh ]] || fail 'gh missing after install'
cp "$MOCK_LOG" "$WORK/before"
"$ROOT/install.sh" --with-gh >/dev/null
cmp "$MOCK_LOG" "$WORK/before" || fail 'existing gh reinstalled'
"$ROOT/install.sh" --uninstall >/dev/null
cmp "$MOCK_LOG" "$WORK/before" || fail 'uninstall invoked sudo'
rm "$MOCK_BIN/gh"
printf 'ID=debian\n' > "$GH_INSTALL_OS_RELEASE"
printf 'y\n' | "$ROOT/scripts/install-gh.sh" >/dev/null
[[ -x $MOCK_BIN/gh ]] || fail 'apt install'
rm "$MOCK_BIN/gh"
printf 'ID=fedora\n' > "$GH_INSTALL_OS_RELEASE"
printf 'y\n' | MOCK_DNF_VERSION=4.0 "$ROOT/scripts/install-gh.sh" >/dev/null
[[ -x $MOCK_BIN/gh ]] || fail 'dnf4 install'
rm "$MOCK_BIN/gh"
printf 'ID=unknown\n' > "$GH_INSTALL_OS_RELEASE"
if "$ROOT/scripts/install-gh.sh" </dev/null >/dev/null 2>&1; then fail 'unsupported accepted'; fi
printf 'ID=fedora\n' > "$GH_INSTALL_OS_RELEASE"
rm "$MOCK_BIN/dnf"
if "$ROOT/scripts/install-gh.sh" </dev/null >/dev/null 2>&1; then fail 'missing dnf accepted'; fi
printf 'GitHub CLI tests passed.\n'
