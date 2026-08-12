#!/usr/bin/env bash
#
# lolfix installer
#
#   curl -fsSL https://raw.githubusercontent.com/lucca-quintas-wh/lolfix-macos/main/install.sh | bash
#
# Or from a clone:  ./install.sh
#
# Override the destination with PREFIX:  PREFIX=/usr/local/bin ./install.sh
#

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/lucca-quintas-wh/lolfix-macos/main/lolfix"
PREFIX="${PREFIX:-$HOME/.local/bin}"
DEST="$PREFIX/lolfix"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi

ok()   { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
die()  { printf '%s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "lolfix is macOS-only (found $(uname -s))."

# Source: the file next to this script when cloned, otherwise fetch it.
SRC=""
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n "$SELF_DIR" && -f "$SELF_DIR/lolfix" ]]; then
  SRC="$SELF_DIR/lolfix"
  printf '%sInstalling from local clone.%s\n' "$DIM" "$RESET"
else
  command -v curl >/dev/null 2>&1 || die "curl not found."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  printf '%sDownloading lolfix...%s\n' "$DIM" "$RESET"
  curl -fsSL "$REPO_RAW" -o "$TMP/lolfix" || die "Download failed."
  SRC="$TMP/lolfix"
fi

# Refuse to install a truncated or corrupted file.
head -1 "$SRC" | grep -q '^#!/usr/bin/env bash' || die "Source doesn't look like lolfix."
bash -n "$SRC" 2>/dev/null || die "Source failed the syntax check."

mkdir -p "$PREFIX" || die "Could not create $PREFIX"

if [[ -e "$DEST" ]] && ! cmp -s "$SRC" "$DEST"; then
  warn "Overwriting the existing $DEST"
fi

install -m 755 "$SRC" "$DEST" || die "Could not write to $DEST (try PREFIX=~/.local/bin)"
ok "Installed to $DEST"

case ":$PATH:" in
  *":$PREFIX:"*)
    ok "$PREFIX is already on your PATH"
    printf '\n%sRun:%s lolfix --help\n' "$BOLD" "$RESET"
    ;;
  *)
    warn "$PREFIX is not on your PATH."
    case "${SHELL##*/}" in
      zsh)  RC="~/.zshrc"  ;;
      bash) RC="~/.bash_profile" ;;
      *)    RC="your shell's rc file" ;;
    esac
    printf '\n  Add this to %s:\n    %sexport PATH="%s:$PATH"%s\n' \
      "$RC" "$BOLD" "$PREFIX" "$RESET"
    printf '\n%sOr run it directly:%s %s --help\n' "$BOLD" "$RESET" "$DEST"
    ;;
esac
