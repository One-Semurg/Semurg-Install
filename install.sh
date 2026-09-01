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
# A2: the download origin MUST be https -- a cleartext origin lets a network attacker swap BOTH the
# installer and the checksum that "verifies" it. Refuse http:// unless the user explicitly opts in.
case "$DL_BASE" in
  https://*) : ;;
  *) if [ "${SEMURG_ALLOW_INSECURE_DL:-}" = 1 ]; then
       echo "WARNING: SEMURG_DL_BASE is not https ($DL_BASE) -- proceeding over cleartext by request." >&2
     else
       echo "error: SEMURG_DL_BASE must be https:// (got '$DL_BASE'). A cleartext origin lets a network attacker replace the installer and its checksum together. Set SEMURG_ALLOW_INSECURE_DL=1 only if you fully trust this network." >&2
       exit 1
     fi ;;
esac
MANIFEST="$DL_BASE/LATEST.json"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required but not installed" >&2; exit 1; }; }
need curl; need tar; need sha256sum; need openssl

echo "Semurg installer -- fetching release manifest ($MANIFEST) ..."
curl -fsSL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 2 "$MANIFEST" -o "$WORK/LATEST.json" \
  || { echo "error: could not reach the Semurg release channel ($MANIFEST). Check https://one.semurg.io status or your network connection, then re-run." >&2; exit 1; }

# --- verify the manifest ed25519 SIGNATURE against a PINNED public key BEFORE trusting anything in it.
#     The signature is produced OFFLINE; compromising the download origin alone cannot forge it. REFUSE if
#     the channel serves no signature or the signature does not verify. ---
SEMURG_RELEASE_PUBKEY='-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAGmSXmU++yNyeIS3rHFjAH1ppyErRrkxcovD6ljt1B4w=
-----END PUBLIC KEY-----'
echo "Verifying release signature (ed25519, pinned key) ..."
curl -fsSL --connect-timeout 15 --max-time 120 --retry 3 --retry-delay 2 "$MANIFEST.sig" -o "$WORK/LATEST.json.sig" \
  || { echo "REFUSING: the release channel served no signature ($MANIFEST.sig); cannot verify authenticity. Nothing installed." >&2; exit 1; }
printf '%s\n' "$SEMURG_RELEASE_PUBKEY" > "$WORK/semurg_release_pub.pem"
openssl pkeyutl -verify -pubin -inkey "$WORK/semurg_release_pub.pem" -rawin -in "$WORK/LATEST.json" -sigfile "$WORK/LATEST.json.sig" >/dev/null 2>&1 \
  || { echo "REFUSING: release manifest signature INVALID -- the download channel may be compromised, or this bootstrap is stale (re-fetch from github.com/One-Semurg/Semurg-Install). Nothing installed." >&2; exit 1; }
echo "  release signature verified"

# Parse JSON without a jq dependency.
val() { grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$WORK/LATEST.json" | head -1 | sed -E "s/.*:[[:space:]]*\"([^\"]*)\"/\1/"; }
VERSION="$(val version)"; URL="$(val installer_url)"; SHA="$(val sha256)"; COMMIT="$(val commit_short)"
[ -n "$URL" ] && [ -n "$SHA" ] || { echo "error: manifest at $MANIFEST is missing installer_url/sha256" >&2; exit 1; }
echo "  current release: version=$VERSION commit=$COMMIT"

TARBALL="$WORK/$(basename "$URL")"
echo "Downloading $URL ..."
curl -fsSL --connect-timeout 15 --max-time 900 --retry 3 --retry-delay 2 "$URL" -o "$TARBALL" \
  || { echo "error: download of the installer bundle failed ($URL). Check your network and re-run; nothing was installed." >&2; exit 1; }

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
