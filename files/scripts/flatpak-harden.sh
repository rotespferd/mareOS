#!/usr/bin/env bash
#
# mareOS build step: ship tightened Flatpak sandbox overrides for the editor.
#
# default-flatpaks installs the apps on first boot, so we cannot `flatpak
# override` at build time (the app isn't installed yet). Instead we write the
# system-wide override files that Flatpak reads at launch. These restrict the
# editor's default broad home/filesystem access; grant per-project folders
# explicitly with Flatseal or `flatpak override --user`.
#
# Ref: https://crftd.tech/blog/2026-05-30-notes-on-safer-development/
#      ("Run in flatpak sandbox with minimal filesystem access")

set -euo pipefail

OVERRIDE_DIR="/etc/flatpak/overrides"
mkdir -p "${OVERRIDE_DIR}"

# VSCodium: drop host filesystem access. The editor can still open files inside
# its sandbox; real builds happen in containers via the Dev Containers flow.
cat > "${OVERRIDE_DIR}/com.vscodium.codium" <<'EOF'
[Context]
filesystems=!host;!home;~/Projects:rw
EOF

echo "flatpak-harden.sh: wrote editor sandbox overrides to ${OVERRIDE_DIR}"
