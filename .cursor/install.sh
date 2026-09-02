#!/usr/bin/env bash
# Cloud Agent environment install for agent-plugins.
#
# Installs the repository's hygiene toolchain — the linters/checkers that the
# committed root configs drive — so every Cloud Agent can run them out of the
# box:
#   markdownlint-cli2    -> .markdownlint-cli2.jsonc
#   editorconfig-checker -> .editorconfig-checker.json
#   typos                -> _typos.toml
#   lychee               -> lychee.toml
#   gitleaks             -> .gitleaks.toml
#
# Design:
#   * Idempotent and safe to re-run. A version stamp plus a presence check gates
#     the whole install, so re-runs (and non-build setup passes) are a no-op once
#     the pinned versions are in place.
#   * No PATH changes required. Standalone binaries land in /usr/local/bin (which
#     is already on PATH); the npm-based markdownlint-cli2 installs into a
#     user-owned prefix and is symlinked into /usr/local/bin.
#   * Writes to /usr/local/bin use sudo only when the directory is not already
#     writable, so it works whether or not the caller owns it.
set -euo pipefail

# Pinned versions. markdownlint-cli2 0.23.2 matches the schema pinned in
# .markdownlint-cli2.jsonc, keeping authoring-time and runtime rules aligned.
MARKDOWNLINT_CLI2_VERSION="0.23.2"
EDITORCONFIG_CHECKER_VERSION="v3.11.2"
TYPOS_VERSION="v1.50.1"
LYCHEE_VERSION="v0.24.2"
GITLEAKS_VERSION="8.30.1"

BIN_DIR="/usr/local/bin"
NPM_PREFIX="${HOME}/.npm-global"
STAMP="${HOME}/.cache/agent-plugins-tools.stamp"

log() { printf 'install: %s\n' "$*" >&2; }

want="markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION} editorconfig-checker@${EDITORCONFIG_CHECKER_VERSION} typos@${TYPOS_VERSION} lychee@${LYCHEE_VERSION} gitleaks@${GITLEAKS_VERSION}"

tools_present() {
  command -v markdownlint-cli2 >/dev/null 2>&1 &&
    command -v editorconfig-checker >/dev/null 2>&1 &&
    command -v typos >/dev/null 2>&1 &&
    command -v lychee >/dev/null 2>&1 &&
    command -v gitleaks >/dev/null 2>&1
}

if tools_present && [[ "$(cat "$STAMP" 2>/dev/null || true)" == "$want" ]]; then
  log "hygiene toolchain already at pinned versions; nothing to do"
  exit 0
fi

arch="$(uname -m)"
if [[ "$arch" != "x86_64" ]]; then
  log "WARNING: this script targets x86_64 Linux; detected '${arch}'. Release URLs may not match."
fi

# install an executable into BIN_DIR, escalating with sudo only when required.
place() {
  local src="$1" name="$2"
  if [[ -w "$BIN_DIR" ]]; then
    install -m0755 "$src" "${BIN_DIR}/${name}"
  else
    sudo install -m0755 "$src" "${BIN_DIR}/${name}"
  fi
}

# symlink a target into BIN_DIR, escalating with sudo only when required.
link() {
  local target="$1" name="$2"
  if [[ -w "$BIN_DIR" ]]; then
    ln -sf "$target" "${BIN_DIR}/${name}"
  else
    sudo ln -sf "$target" "${BIN_DIR}/${name}"
  fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Download over an HTTPS-pinned redirect chain; a couple of retries absorb
# transient network blips during setup.
fetch() {
  curl -fsSL --retry 3 --retry-delay 2 --proto '=https' --proto-redir '=https' "$1" -o "$2"
}

# extract_first <tarball> <dest-dir> <basename> -> path to the extracted file.
# Release tarballs differ in layout (flat vs. nested dir), so locate by name.
extract_first() {
  local tarball="$1" dest="$2" name="$3"
  mkdir -p "$dest"
  tar -xzf "$tarball" -C "$dest"
  find "$dest" -type f -name "$name" | head -1
}

# --- markdownlint-cli2 (npm package; no standalone binary is published) -------
log "installing markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}"
mkdir -p "$NPM_PREFIX"
npm install -g --prefix "$NPM_PREFIX" "markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}" >/dev/null 2>&1
link "${NPM_PREFIX}/bin/markdownlint-cli2" markdownlint-cli2

# --- editorconfig-checker (standalone Go binary) -----------------------------
# The npm wrapper lazily downloads its binary at first run; the release binary
# avoids that runtime network dependency and is snapshot-friendly.
log "installing editorconfig-checker ${EDITORCONFIG_CHECKER_VERSION}"
fetch "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/${EDITORCONFIG_CHECKER_VERSION}/ec-linux-amd64.tar.gz" "${work}/ec.tgz"
place "$(extract_first "${work}/ec.tgz" "${work}/ec" 'ec-linux-amd64')" editorconfig-checker

# --- typos (standalone binary) -----------------------------------------------
log "installing typos ${TYPOS_VERSION}"
fetch "https://github.com/crate-ci/typos/releases/download/${TYPOS_VERSION}/typos-${TYPOS_VERSION}-x86_64-unknown-linux-musl.tar.gz" "${work}/typos.tgz"
place "$(extract_first "${work}/typos.tgz" "${work}/typos" 'typos')" typos

# --- lychee (standalone binary) ----------------------------------------------
log "installing lychee ${LYCHEE_VERSION}"
fetch "https://github.com/lycheeverse/lychee/releases/download/lychee-${LYCHEE_VERSION}/lychee-x86_64-unknown-linux-gnu.tar.gz" "${work}/lychee.tgz"
place "$(extract_first "${work}/lychee.tgz" "${work}/lychee" 'lychee')" lychee

# --- gitleaks (standalone binary) --------------------------------------------
log "installing gitleaks ${GITLEAKS_VERSION}"
fetch "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" "${work}/gitleaks.tgz"
place "$(extract_first "${work}/gitleaks.tgz" "${work}/gitleaks" 'gitleaks')" gitleaks

mkdir -p "$(dirname "$STAMP")"
printf '%s' "$want" >"$STAMP"

log "hygiene toolchain installed:"
log "  markdownlint-cli2    v${MARKDOWNLINT_CLI2_VERSION}"
log "  editorconfig-checker ${EDITORCONFIG_CHECKER_VERSION}"
log "  typos                ${TYPOS_VERSION}"
log "  lychee               ${LYCHEE_VERSION}"
log "  gitleaks             ${GITLEAKS_VERSION}"
