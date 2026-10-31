#!/usr/bin/env sh
# Stops the container, which removes it and its volumes, then removes what
# up.sh and Conn3x created here.
set -eu
cd "$(dirname "$0")"
${PODMAN:-podman} stop --ignore "${NAME:-circuit-containerd}" >/dev/null
rm -rf id_ed25519 id_ed25519.pub known_hosts .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
echo "Removed."
