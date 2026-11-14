#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
export HOME="$WORK/home with spaces"
export XDG_CONFIG_HOME="$HOME/custom config"
# Ignore inherited Git configuration and never contact a user's tmux server.
unset GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
export GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { "$ROOT/install.sh" "$@"; }
backup_count() { find "$HOME" -name '*.backup-*' | wc -l; }
# A missing application must leave the target home empty.
mkdir -p "$WORK/missing-bin" "$WORK/missing-home"
for tool in bash dirname mktemp rm; do ln -s "$(command -v "$tool")" "$WORK/missing-bin/$tool"; done
if HOME="$WORK/missing-home" XDG_CONFIG_HOME="$WORK/missing-home/.config" PATH="$WORK/missing-bin" "$ROOT/install.sh"; then
    fail 'missing dependency accepted'
fi
[[ -z $(find "$WORK/missing-home" -mindepth 1 -print -quit) ]] || fail 'missing dependency changed home'
# Freeze timestamps so repeated backups must exercise collision handling.
mkdir "$WORK/clock-bin"
printf '#!/usr/bin/env bash\nprintf "20000101-000000\\n"\n' > "$WORK/clock-bin/date"
chmod +x "$WORK/clock-bin/date"
export PATH="$WORK/clock-bin:$PATH"

TARGET=$HOME/.gitconfig
printf '[user]\n    name = Test User\n    email = test@example.invalid\n[pull]\n    ff = false\n' > "$TARGET"
cp "$TARGET" "$WORK/original"
run
[[ $(git config --includes user.name) == 'Test User' ]] || fail identity
[[ $(git config --includes pull.ff) == false ]] || fail precedence
[[ $(git config --includes init.defaultBranch) == master ]] || fail defaults

git init -q "$WORK/repo"
git -C "$WORK/repo" st >/dev/null
first=$(backup_count)
run
[[ $(backup_count) == "$first" ]] || fail idempotency
printf '[pull]\n    ff = only\n' > "$HOME/.gitconfig.local"
[[ $(git config --includes pull.ff) == only ]] || fail 'local override'
run --uninstall
cmp "$TARGET" "$WORK/original" || fail 'original not restored'
[[ -f $HOME/.gitconfig.local ]] || fail 'local file removed'
rm "$HOME/.gitconfig.local"
# XDG values must retain precedence, with ~/.gitconfig still later.
mkdir -p "$XDG_CONFIG_HOME/git"
printf '[diff]\n    algorithm = patience\n' > "$XDG_CONFIG_HOME/git/config"
run
[[ $(git config --includes diff.algorithm) == patience ]] || fail 'XDG precedence'
run --uninstall
# Symlink entrypoints are refused without following or replacing them.
rm "$TARGET"
ln -s "$WORK/original" "$TARGET"
if run; then fail 'symlink entrypoint accepted'; fi
[[ -L $TARGET ]] || fail 'symlink modified'
rm "$TARGET"
printf '[broken\n' > "$TARGET"
if run; then fail 'malformed config accepted'; fi
[[ $(cat "$TARGET") == '[broken' ]] || fail 'malformed file changed'
rm "$TARGET"
# Fresh home and foreign/broken managed symlinks.
rm "$XDG_CONFIG_HOME/git/config"
mkdir -p "$XDG_CONFIG_HOME/git-setup"
ln -s "$WORK/missing" "$XDG_CONFIG_HOME/git-setup/gitconfig"
run
[[ -L $XDG_CONFIG_HOME/git-setup/gitconfig ]] || fail 'managed link'
[[ $(git config --includes alias.sw) == switch ]] || fail alias
# The pager handles missing delta, and delta appearing later, without reinstalling.
mkdir "$WORK/bin"
for tool in bash cat; do ln -s "$(command -v "$tool")" "$WORK/bin/$tool"; done
printf 'pager fallback\n' | PATH="$WORK/bin" "$ROOT/scripts/pager.sh" | grep -q 'pager fallback' || fail 'cat fallback'
cat > "$WORK/bin/delta" <<'DELTA'
#!/usr/bin/env bash
printf 'delta selected\n'
cat
DELTA
chmod +x "$WORK/bin/delta"
printf 'input\n' | PATH="$WORK/bin" "$ROOT/scripts/pager.sh" | grep 'delta selected' >/dev/null || fail delta
# The configured shell command must resolve paths containing spaces.
pager=$(git config --includes core.pager)
printf 'input\n' | PATH="$WORK/bin" /bin/sh -c "$pager" | grep 'delta selected' >/dev/null || fail 'configured pager path'
run --uninstall
# Also exercise a fresh home using the default XDG location.
export HOME="$WORK/fresh-home"
unset XDG_CONFIG_HOME
mkdir -p "$HOME"
run
[[ -L $HOME/.config/git-setup/gitconfig ]] || fail 'fresh default-location install'
run
run --uninstall
[[ ! -L $HOME/.config/git-setup/gitconfig ]] || fail 'fresh default-location uninstall'
echo 'Installer tests passed.'
