#!/usr/bin/env bash
# Semurg one-command installer bootstrap.
#
# Fetches the CURRENT release manifest (one.semurg.io/dl/LATEST.json), downloads the installer bundle,
# VERIFIES its sha256, unpacks it, and runs the bundled installer. Version-agnostic: it always installs
# the latest published release, so this script does not change between releases.
#
# It downloads the RELEASED Semurg engine only. This repository contains no engine source.
#
# Usage:
#   curl -fsSLO https://raw.githubusercontent.com/One-Semurg/Semurg-Install/main/install.sh
#   less install.sh                 # read it before you run it
#   sudo bash install.sh            # installs a systemd unit; needs root
#
# Override the download origin (e.g. an internal mirror) with SEMURG_DL_BASE.
set -euo pipefail

DL_BASE="${SEMURG_DL_BASE:-https://one.semurg.io/dl}"
MANIFEST="$DL_BASE/LATEST.json"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required but not installed" >&2; exit 1; }; }
need curl; need tar; need sha256sum

echo "Semurg installer -- fetching release manifest ($MANIFEST) ..."
curl -fsSL "$MANIFEST" -o "$WORK/LATEST.json"

# Parse JSON without a jq dependency.
val() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$WORK/LATEST.json" | head -1 | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/"; }
VERSION="$(val version)"; URL="$(val installer_url)"; SHA="$(val sha256)"; COMMIT="$(val commit_short)"
[ -n "$URL" ] && [ -n "$SHA" ] || { echo "error: manifest at $MANIFEST is missing installer_url/sha256" >&2; exit 1; }
echo "  current release: version=$VERSION commit=$COMMIT"

TARBALL="$WORK/$(basename "$URL")"
echo "Downloading $URL ..."
curl -fsSL "$URL" -o "$TARBALL"

echo "Verifying sha256 ..."
echo "${SHA}  ${TARBALL}" | sha256sum -c - \
  || { echo "CHECKSUM MISMATCH -- aborting. Refusing to run an unverified installer." >&2; exit 1; }

echo "Unpacking ..."
tar xzf "$TARBALL" -C "$WORK"
DIR="$(find "$WORK" -maxdepth 2 -type d -name 'semurg_installer' | head -1)"
[ -n "$DIR" ] && [ -x "$DIR/semurg-install.sh" ] \
  || { echo "error: installer entry (semurg_installer/semurg-install.sh) not found in bundle" >&2; exit 1; }

echo "Running the Semurg installer (preflight -> hardware scan -> install -> start; installs a systemd unit) ..."
cd "$DIR"
if [ "$(id -u)" -eq 0 ]; then
  ./semurg-install.sh "$@"
else
  echo "  (re-running the bundled installer under sudo)"
  sudo ./semurg-install.sh "$@"
fi

cat <<'DONE'

Semurg is installed. Next:
  * Web console:  http://<this-host>:4000       (locally: http://localhost:4000)
  * Data API:     http://<this-host>:4000/v1    (load and query your own data)
  * Admin UI:     auto-provisioned during install -- the one-time admin secret + console URL are in the
                  SUCCESS banner above (also saved to /opt/semurg/tmp/.admin_bootstrap_banner). Save it.
See https://github.com/One-Semurg/Semurg-Install for the full guide.
DONE
