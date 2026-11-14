#!/usr/bin/env bash
set -euo pipefail
manual='https://github.com/cli/cli/blob/trunk/docs/install_linux.md'
fail() { echo "Error: $* See $manual" >&2; exit 1; }
next_steps() { printf 'GitHub authentication is optional. When ready, run:\n  gh auth login\n  gh auth status\n'; }
if command -v gh >/dev/null 2>&1; then
    gh --version || fail 'Could not read the installed gh version.'
    next_steps
    exit 0
fi
# Read only the distribution identifiers, without executing os-release contents.
os_release=${GH_INSTALL_OS_RELEASE:-/etc/os-release}
[[ -r $os_release ]] || fail 'Cannot identify this Linux distribution.'
id=$(sed -n 's/^ID=//p' "$os_release" | tr -d '"' | head -n 1)
case $id in
    fedora)
        command -v dnf >/dev/null 2>&1 || fail 'Fedora requires dnf.'
        version=$(dnf --version | head -n 1)
        version=${version#dnf5 version }
        case $version in 5.*) dnf_version=5 ;; 4.*) dnf_version=4 ;; *) fail 'Unsupported dnf version.' ;; esac
        echo "This will use sudo to install the DNF $dnf_version config-manager plugin, configure GitHub's RPM repository, and install gh."
        ;;
    ubuntu|debian)
        for tool in apt-get dpkg wget; do command -v "$tool" >/dev/null 2>&1 || fail "Missing $tool."; done
        echo "This will use sudo to add GitHub's apt signing key and repository, update package lists, and install gh."
        ;;
    *) fail "Unsupported distribution: ${id:-unknown}." ;;
esac
command -v sudo >/dev/null 2>&1 || fail 'sudo is required.'
printf 'Continue? [y/N] '
read -r answer || answer=
[[ $answer == y || $answer == Y || $answer == yes || $answer == YES ]] || { echo 'Installation declined.' >&2; exit 1; }
if [[ $id == fedora ]]; then
    if [[ $dnf_version == 5 ]]; then
        sudo dnf install dnf5-plugins || fail 'DNF plugin installation failed.'
        sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo || fail 'DNF repository setup failed.'
    else
        sudo dnf install 'dnf-command(config-manager)' || fail 'DNF plugin installation failed.'
        sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo || fail 'DNF repository setup failed.'
    fi
    sudo dnf install gh || fail 'DNF installation failed.'
else
    key=$(mktemp)
    trap 'rm -f -- "$key"' EXIT
    wget -nv -O "$key" https://cli.github.com/packages/githubcli-archive-keyring.gpg || fail 'Signing key download failed.'
    arch=$(dpkg --print-architecture) || fail 'Could not detect package architecture.'
    sudo mkdir -p -m 755 /etc/apt/keyrings /etc/apt/sources.list.d || fail 'APT directory setup failed.'
    sudo install -m 644 "$key" /etc/apt/keyrings/githubcli-archive-keyring.gpg || fail 'APT key setup failed.'
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$arch" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null || fail 'APT repository setup failed.'
    sudo apt-get update || fail 'APT update failed.'
    sudo apt-get install gh || fail 'APT installation failed.'
fi
command -v gh >/dev/null 2>&1 || fail 'Installation finished but gh could not be found.'
gh --version || fail 'Installed gh could not be verified.'
next_steps
