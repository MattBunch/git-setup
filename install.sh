#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODE=${1:-install}
[[ $# -le 1 && ( $MODE == install || $MODE == --with-gh || $MODE == --uninstall ) ]] || { echo "Usage: $0 [--with-gh|--uninstall]" >&2; exit 1; }
: "${HOME:?HOME must be set}"
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
[[ $HOME == /* && $CONFIG_HOME == /* ]] || { echo 'HOME and XDG_CONFIG_HOME must be absolute.' >&2; exit 1; }
fail() { echo "Error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Missing $1. $2"; }
check_path() { [[ ! -d $1 || -L $1 ]] || fail "Refusing directory: $1"; }
backup() {
    local dest n=0
    dest="$1.backup-$(date +%Y%m%d-%H%M%S)"
    while [[ -e $dest || -L $dest ]]; do n=$((n + 1)); dest="$1.backup-$(date +%Y%m%d-%H%M%S)-$n"; done
    mv -- "$1" "$dest"
    echo "Backup: $dest"
}
link_file() {
    local src=$1 dest=$2
    if [[ -L $dest && $(readlink -- "$dest") == "$src" ]]; then echo "Unchanged: $dest"; return; fi
    check_path "$dest"
    mkdir -p -- "$(dirname -- "$dest")"
    if [[ -e $dest || -L $dest ]]; then backup "$dest"; fi
    ln -s -- "$src" "$dest"
    echo "Linked: $dest -> $src"
}
unlink_owned() {
    if [[ -L $2 && $(readlink -- "$2") == "$1" ]]; then rm -- "$2"; echo "Removed: $2"; fi
}

need git 'Install with: sudo dnf install git; or sudo apt install git.'
need cmp 'Install diffutils: sudo dnf install diffutils; or sudo apt install diffutils.'
# Select the earliest global file so existing XDG and ~/.gitconfig values win.
EARLY=$HOME/.gitconfig
if [[ -e $CONFIG_HOME/git/config || -L $CONFIG_HOME/git/config ]]; then EARLY=$CONFIG_HOME/git/config; fi
LATE=$HOME/.gitconfig
MANAGED=$CONFIG_HOME/git-setup
[[ $ROOT != *$'\n'* && $HOME != *$'\n'* && $CONFIG_HOME != *$'\n'* ]] || fail 'Newlines in paths are unsupported.'
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

# Strip only our own blocks. Incomplete or foreign blocks need manual review.
strip_blocks() {
    local file=$1 out=$2
    if [[ ! -e $file ]]; then : > "$out"; return; fi
    awk -v owner="$ROOT" '
      /^# BEGIN git-setup / {
        if (inside || $0 != "# BEGIN git-setup defaults: " owner && $0 != "# BEGIN git-setup local: " owner) exit 1
        inside=1; expected=$0; sub("BEGIN", "END", expected); next
      }
      /^# END git-setup / { if (!inside || $0 != expected) exit 1; inside=0; next }
      !inside { print }
      END { if (inside) exit 1 }
    ' "$file" > "$out" || fail "Unrecognised managed block in $file; review it manually."
}
for file in "$EARLY" "$LATE"; do
    check_path "$file"
    [[ ! -L $file ]] || fail "Symlinked Git configuration: $file. Add includes manually; see README."
    if [[ -e $file ]]; then git config --file "$file" --includes --list >/dev/null || fail "Invalid Git configuration: $file"; fi
done
check_path "$MANAGED/gitconfig"
check_path "$MANAGED/pager.sh"
strip_blocks "$EARLY" "$WORK/early"
if [[ $LATE != "$EARLY" ]]; then strip_blocks "$LATE" "$WORK/late"; fi

write_config() {
    local file=$1 content=$2
    if [[ -e $file ]] && cmp -s -- "$file" "$content"; then echo "Unchanged: $file"; return; fi
    # Uninstall must not create a file that never existed.
    if [[ $MODE == --uninstall && ! -e $file ]]; then return; fi
    mkdir -p -- "$(dirname -- "$file")"
    local tmp
    tmp=$(mktemp "$(dirname -- "$file")/.git-setup.XXXXXX")
    cat -- "$content" > "$tmp"
    if [[ -e $file ]]; then chmod --reference="$file" "$tmp"; backup "$file"; fi
    mv -- "$tmp" "$file"
    echo "Updated: $file"
}
if [[ $MODE == --uninstall ]]; then
    write_config "$EARLY" "$WORK/early"
    if [[ $LATE != "$EARLY" ]]; then write_config "$LATE" "$WORK/late"; fi
    unlink_owned "$ROOT/gitconfig" "$MANAGED/gitconfig"
    unlink_owned "$ROOT/scripts/pager.sh" "$MANAGED/pager.sh"
    echo 'Local settings and backups retained.'
    exit
fi
version=$(git --version | awk '{print $3}')
IFS=. read -r major minor _ <<< "$version"
(( major > 2 || major == 2 && minor >= 34 )) || fail 'Git 2.34+ is required.'
# Let Git quote paths correctly, including spaces and backslashes.
git config --file "$WORK/include" include.path "$MANAGED/gitconfig"
git config --file "$WORK/local" include.path "$HOME/.gitconfig.local"
{
    echo "# BEGIN git-setup defaults: $ROOT"
    cat "$WORK/include"
    echo "# END git-setup defaults: $ROOT"
    cat "$WORK/early"
} > "$WORK/new-early"
if [[ $EARLY == "$LATE" ]]; then cp "$WORK/new-early" "$WORK/new-late"; else cp "$WORK/late" "$WORK/new-late"; fi
{
    echo "# BEGIN git-setup local: $ROOT"
    cat "$WORK/local"
    echo "# END git-setup local: $ROOT"
} >> "$WORK/new-late"
link_file "$ROOT/gitconfig" "$MANAGED/gitconfig"
link_file "$ROOT/scripts/pager.sh" "$MANAGED/pager.sh"
if [[ $EARLY != "$LATE" ]]; then write_config "$EARLY" "$WORK/new-early"; fi
write_config "$LATE" "$WORK/new-late"
echo "Installed Git defaults. Private overrides: $HOME/.gitconfig.local"
if [[ $MODE == --with-gh ]]; then
    if ! "$ROOT/scripts/install-gh.sh"; then
        echo 'Git configuration remains installed; GitHub CLI installation was not completed.' >&2
        exit 1
    fi
fi
