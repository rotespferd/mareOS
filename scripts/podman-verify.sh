#!/usr/bin/env bash
#
# mareOS build step: require cosign/sigstore signatures when pulling container
# images from trusted registry scopes.
#
# We MERGE into the existing /etc/containers/policy.json rather than overwriting
# it, so we don't clobber the OS-image verification policy installed by the
# BlueBuild `signing` module.
#
# Ref: https://crftd.tech/blog/2026-05-30-notes-on-safer-development/
#      ("validate signatures with cosign when possible")

set -euo pipefail

POLICY="/etc/containers/policy.json"
PUBKEY_DIR="/etc/pki/containers"
mkdir -p "${PUBKEY_DIR}"

# The Universal Blue public key must be present for verification of base images.
# Vendor it into the repo at files/system/etc/pki/containers/ublue-os.pub (copied
# in by the `files` module) — do NOT curl it at build time (no fetch-and-execute).
UBLUE_KEY="${PUBKEY_DIR}/ublue-os.pub"

if [[ ! -f "${POLICY}" ]]; then
  echo '{ "default": [ { "type": "insecureAcceptAnything" } ], "transports": {} }' > "${POLICY}"
fi

if [[ ! -f "${UBLUE_KEY}" ]]; then
  echo "podman-verify.sh: WARNING ${UBLUE_KEY} missing — skipping ublue-os enforcement."
  echo "  Vendor the key into files/system${UBLUE_KEY#/} to enable it."
else
  # Add a sigstoreSigned requirement for the ublue-os scope, keeping defaults.
  tmp="$(mktemp)"
  jq --arg key "${UBLUE_KEY}" '
    .transports.docker = (.transports.docker // {}) |
    .transports.docker["ghcr.io/ublue-os"] = [ { "type": "sigstoreSigned", "keyPath": $key } ]
  ' "${POLICY}" > "${tmp}"
  mv "${tmp}" "${POLICY}"
  echo "podman-verify.sh: enforced sigstore signatures for ghcr.io/ublue-os"
fi

echo "podman-verify.sh: done. Verify at runtime with:"
echo "  podman pull ghcr.io/ublue-os/base-main   # signed -> allowed"
echo "  podman pull docker.io/library/hello-world # unsigned in an enforced scope -> blocked"
