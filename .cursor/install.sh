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
#   * Idempotent and safe to re-run. Skip a tool only when the binary this
#     script installs ($BIN_DIR/<name>) reports the expected version AND
#     `command -v <name>` resolves to that same file. A stamp is written after
#     a successful pass as a record; it is never consulted to skip work.
#   * No PATH changes required. Standalone binaries land in /usr/local/bin
#     (already on PATH); markdownlint-cli2 (npm-only) installs into a
#     user-owned prefix and is symlinked into /usr/local/bin.
#   * Writes to /usr/local/bin use sudo only when the directory is not already
#     writable, so it works whether or not the caller owns it.
set -euo pipefail

# Pinned versions. markdownlint-cli2 0.23.2 matches the schema pinned in
# .markdownlint-cli2.jsonc, keeping authoring-time and runtime rules aligned.
MARKDOWNLINT_CLI2_VERSION="0.23.2"
# NOTE: the editorconfig-checker v3.11.2 release binary self-reports "v3.11.1"
# (an upstream version-embedding quirk); `editorconfig-checker --version`
# printing v3.11.1 is expected and does not mean the wrong binary was installed.
EDITORCONFIG_CHECKER_VERSION="v3.11.2"
EDITORCONFIG_CHECKER_REPORTS="3.11.1"
TYPOS_VERSION="v1.50.1"
LYCHEE_VERSION="v0.24.2"
GITLEAKS_VERSION="8.30.1"

BIN_DIR="/usr/local/bin"
NPM_PREFIX="${HOME}/.npm-global"
STAMP="${HOME}/.cache/agent-plugins-tools.stamp"

log() { printf 'install: %s\n' "$*" >&2; }

want="markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION} editorconfig-checker@${EDITORCONFIG_CHECKER_VERSION} typos@${TYPOS_VERSION} lychee@${LYCHEE_VERSION} gitleaks@${GITLEAKS_VERSION}"

# First complete X.Y.Z (optional leading v), then strip the v. Exact token
# compare — "1.50.10" must not satisfy a pin of "1.50.1".
semver_token() {
  local raw
  raw="$(printf '%s' "$1" | grep -oE '[vV]?[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
  [[ -n "$raw" ]] || return 1
  raw="${raw#v}"
  raw="${raw#V}"
  printf '%s' "$raw"
}

# Official version invocations:
#   markdownlint-cli2 — `--version` is a glob (DavidAnson/markdownlint-cli2#289);
#     `--help` prints "markdownlint-cli2 vX.Y.Z (markdownlint vX.Y.Z)" and exits.
#   editorconfig-checker — `--version`
#   typos — `--version` (prints "typos-cli X.Y.Z")
#   lychee — `--version`
#   gitleaks — `version` subcommand (README "Available Commands")
tool_report() {
  local bin="$1" name="$2" out
  case "$name" in
    markdownlint-cli2)
      # `--help` prints "markdownlint-cli2 vX.Y.Z (...)" then exits 2
      # (DavidAnson/markdownlint-cli2 — help is not a zero-exit path).
      # Capture the full banner; do not pipe to `head` (SIGPIPE + pipefail).
      out="$("$bin" --help 2>&1 || true)"
      printf '%s\n' "${out%%$'\n'*}"
      ;;
    editorconfig-checker)
      "$bin" --version 2>&1
      ;;
    typos)
      "$bin" --version 2>&1
      ;;
    lychee)
      "$bin" --version 2>&1
      ;;
    gitleaks)
      "$bin" version 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

expected_semver() {
  case "$1" in
    markdownlint-cli2) printf '%s' "$MARKDOWNLINT_CLI2_VERSION" ;;
    editorconfig-checker) printf '%s' "$EDITORCONFIG_CHECKER_REPORTS" ;;
    typos) printf '%s' "${TYPOS_VERSION#v}" ;;
    lychee) printf '%s' "${LYCHEE_VERSION#v}" ;;
    gitleaks) printf '%s' "$GITLEAKS_VERSION" ;;
    *) return 1 ;;
  esac
}

same_file() {
  local a="$1" b="$2"
  [[ -e "$a" && -e "$b" ]] || return 1
  [[ "$(readlink -f -- "$a")" == "$(readlink -f -- "$b")" ]]
}

# True only when $BIN_DIR/$name exists, reports the pinned semver, and is the
# executable `command -v` would run (so a PATH shadow cannot skip install).
tool_ok() {
  local name="$1"
  local canonical="${BIN_DIR}/${name}"
  local resolved report got want_ver
  [[ -x "$canonical" ]] || return 1
  resolved="$(command -v "$name" 2>/dev/null || true)"
  [[ -n "$resolved" ]] || return 1
  same_file "$resolved" "$canonical" || return 1
  report="$(tool_report "$canonical" "$name")" || return 1
  got="$(semver_token "$report")" || return 1
  want_ver="$(expected_semver "$name")" || return 1
  [[ "$got" == "$want_ver" ]]
}

arch="$(uname -m)"
if [[ "$arch" != "x86_64" ]]; then
  log "WARNING: this script targets x86_64 Linux; detected '${arch}'. Release URLs may not match."
fi

# install an executable into BIN_DIR, escalating with sudo only when required.
place() {
  local src="$1" name="$2"
  [[ -n "$src" && -f "$src" ]] || {
    log "ERROR: nothing to install for ${name}"
    return 1
  }
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

work=""
ensure_work() {
  if [[ -z "$work" ]]; then
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
  fi
}

# Download over an HTTPS-pinned redirect chain; a couple of retries absorb
# transient network blips during setup.
fetch() {
  curl -fsSL --retry 3 --retry-delay 2 --proto '=https' --proto-redir '=https' "$1" -o "$2"
}

# extract_first <tarball> <dest-dir> <basename> -> path to the extracted file.
# Release tarballs differ in layout (flat vs. nested dir), so locate by name.
extract_first() {
  local tarball="$1" dest="$2" name="$3" found
  mkdir -p "$dest"
  tar -xzf "$tarball" -C "$dest"
  found="$(find "$dest" -type f -name "$name" -print -quit)"
  [[ -n "$found" ]] || {
    log "ERROR: ${name} not found in ${tarball}"
    return 1
  }
  printf '%s' "$found"
}

install_markdownlint_cli2() {
  log "installing markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}"
  mkdir -p "$NPM_PREFIX"
  npm install -g --prefix "$NPM_PREFIX" "markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}" >/dev/null
  link "${NPM_PREFIX}/bin/markdownlint-cli2" markdownlint-cli2
}

install_editorconfig_checker() {
  # The npm wrapper lazily downloads its binary at first run; the release
  # binary avoids that runtime network dependency and is snapshot-friendly.
  log "installing editorconfig-checker ${EDITORCONFIG_CHECKER_VERSION}"
  ensure_work
  fetch "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/${EDITORCONFIG_CHECKER_VERSION}/ec-linux-amd64.tar.gz" "${work}/ec.tgz"
  place "$(extract_first "${work}/ec.tgz" "${work}/ec" 'ec-linux-amd64')" editorconfig-checker
}

install_typos() {
  log "installing typos ${TYPOS_VERSION}"
  ensure_work
  fetch "https://github.com/crate-ci/typos/releases/download/${TYPOS_VERSION}/typos-${TYPOS_VERSION}-x86_64-unknown-linux-musl.tar.gz" "${work}/typos.tgz"
  place "$(extract_first "${work}/typos.tgz" "${work}/typos" 'typos')" typos
}

install_lychee() {
  log "installing lychee ${LYCHEE_VERSION}"
  ensure_work
  fetch "https://github.com/lycheeverse/lychee/releases/download/lychee-${LYCHEE_VERSION}/lychee-x86_64-unknown-linux-gnu.tar.gz" "${work}/lychee.tgz"
  place "$(extract_first "${work}/lychee.tgz" "${work}/lychee" 'lychee')" lychee
}

install_gitleaks() {
  log "installing gitleaks ${GITLEAKS_VERSION}"
  ensure_work
  fetch "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" "${work}/gitleaks.tgz"
  place "$(extract_first "${work}/gitleaks.tgz" "${work}/gitleaks" 'gitleaks')" gitleaks
}

install_named() {
  case "$1" in
    markdownlint-cli2) install_markdownlint_cli2 ;;
    editorconfig-checker) install_editorconfig_checker ;;
    typos) install_typos ;;
    lychee) install_lychee ;;
    gitleaks) install_gitleaks ;;
    *)
      log "ERROR: unknown tool $1"
      return 1
      ;;
  esac
}

ensure_tool() {
  local name="$1"
  if tool_ok "$name"; then
    log "${name} already at expected version ($(expected_semver "$name"))"
    return 0
  fi
  install_named "$name"
  if ! tool_ok "$name"; then
    log "ERROR: ${name} is not at expected version $(expected_semver "$name") after install (PATH=$(command -v "$name" 2>/dev/null || echo missing))"
    return 1
  fi
  log "${name} installed and verified ($(expected_semver "$name"))"
}

installed_any=0
for tool in markdownlint-cli2 editorconfig-checker typos lychee gitleaks; do
  if tool_ok "$tool"; then
    log "${tool} already at expected version ($(expected_semver "$tool"))"
  else
    installed_any=1
    ensure_tool "$tool"
  fi
done

for tool in markdownlint-cli2 editorconfig-checker typos lychee gitleaks; do
  if ! tool_ok "$tool"; then
    log "ERROR: post-pass verification failed for ${tool}"
    exit 1
  fi
done

mkdir -p "$(dirname "$STAMP")"
printf '%s' "$want" >"$STAMP"

if [[ "$installed_any" -eq 0 ]]; then
  log "hygiene toolchain already at pinned versions; nothing to do"
else
  log "hygiene toolchain installed:"
  log "  markdownlint-cli2    v${MARKDOWNLINT_CLI2_VERSION}"
  log "  editorconfig-checker ${EDITORCONFIG_CHECKER_VERSION} (reports v${EDITORCONFIG_CHECKER_REPORTS})"
  log "  typos                ${TYPOS_VERSION}"
  log "  lychee               ${LYCHEE_VERSION}"
  log "  gitleaks             ${GITLEAKS_VERSION}"
fi
