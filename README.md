# git-setup

Portable Git defaults that fit alongside your existing configuration.

## Features

- Short aliases: `st`, `sw`, `br`, `ci`, `unstage`, `last`, and `lg`.
- New repositories use `master`; pulls require a fast-forward; fetch removes stale remote branches.
- Histogram diffs, moved-line highlighting, and conflict markers with the original text.
- Uses delta when available, otherwise less or plain output.

Existing global settings take precedence. Identity, credentials, signing, editor,
and line-ending settings are left to you.

## Platforms

Fedora, Ubuntu/Debian, and WSL2 with Bash and Git 2.34+.
Install Git first: `sudo dnf install git diffutils` or `sudo apt install git diffutils`.
The default installer never installs packages or uses sudo. Delta is optional.

## Install

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/MattBunch/git-setup.git
cd git-setup
./install.sh
# Or also install GitHub CLI:
./install.sh --with-gh
```

GitHub CLI (`gh`) lets you work with GitHub from the terminal. It is optional;
the installer supports Fedora, Ubuntu and Debian, including WSL2. If `gh` is
already installed, its version is shown and installation is skipped. Otherwise,
the helper explains its package and repository changes and asks before using sudo.
Afterwards, authenticate when you choose:

```bash
gh auth login
gh auth status
```

Authentication is never performed automatically.

The installer links configuration and a pager under
`${XDG_CONFIG_HOME:-$HOME/.config}/git-setup`. It adds marked include blocks to
Git's global files, preserving existing settings. If an XDG Git configuration
exists, defaults are included there first; otherwise they go in `~/.gitconfig`.
A final include in `~/.gitconfig` loads your private overrides.

Changed files and foreign links receive adjacent `.backup-<timestamp>` backups,
with a unique suffix if needed. Re-running makes no changes when already installed.
Keep the checkout in place because the installed links point to it.

## Customise

Put identity and overrides in `~/.gitconfig.local`, outside the repository:

```bash
git config --file ~/.gitconfig.local user.name 'Your Name'
git config --file ~/.gitconfig.local user.email 'you@example.com'
```

Never commit that file. Use Git's `includeIf` in your own configuration for
separate work and personal identities. Inspect effective settings with
`git config --list --show-origin` (the output may contain private values).

Symlinked global files, malformed configuration, or another checkout's managed
blocks are refused. For manual integration, include the checkout's `gitconfig`
before your own settings and `~/.gitconfig.local` afterwards. Leave `core.pager`
overridden locally unless you also install the pager link described above.

## Update or uninstall

```bash
cd ~/Projects/git-setup
git pull --ff-only
./install.sh
# To uninstall:
./install.sh --uninstall
```

Uninstall removes this checkout's includes and owned links, keeping GitHub CLI, your settings
and backups. To restore a backup, inspect it first, move the current file aside,
then run `mv -- '/path/to/file.backup-TIMESTAMP' '/path/to/file'`.
Backups may contain private settings; keep them private.

CI checks Bash, ShellCheck, and isolated installer tests on three Linux distributions.
Run the tests yourself with `bash tests/install.sh`.
