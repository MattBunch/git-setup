#!/usr/bin/env bash
set -euo pipefail
if command -v delta >/dev/null 2>&1; then
    exec delta "$@"
elif command -v less >/dev/null 2>&1; then
    exec less -FRX "$@"
else
    exec cat "$@"
fi
