#!/usr/bin/env sh
# Starts a throwaway host on 127.0.0.1:$PORT (default 2312) that Conn3x can
# configure, with a fresh SSH key and its host key in ./known_hosts.
# CONTAINERFILE picks another image, such as one of Conn3x's test images.
# Needs Podman, since the host runs systemd.
# containerd needs a privileged container with /var/lib/containerd on a volume,
# where it can use overlayfs. Rootful Podman is simplest:
# CONTAINER_CONNECTION=podman-machine-default-root on a Mac, or
# PODMAN="sudo podman" on Linux.
set -eu
cd "$(dirname "$0")"
port=${PORT:-2312}
containerfile=${CONTAINERFILE:-Containerfile}
name=${NAME:-circuit-containerd}

podman=${PODMAN:-podman}
if $podman container exists "$name"; then
  echo "A container named $name is already there. Run ./down.sh first." >&2
  exit 1
fi
[ -f id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -C "$name" -f id_ed25519
$podman build -q -f "$containerfile" -t "$name" "$(dirname "$containerfile")" >/dev/null
# --rm: stopping the container also removes it and its volumes.
$podman run -d --rm --name "$name" --systemd=always --privileged -v /var/lib/containerd \
  -p "127.0.0.1:$port:22" "$name" >/dev/null
$podman exec -i "$name" sh -c 'cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys' < id_ed25519.pub
$podman exec "$name" timeout 60 systemctl is-system-running --wait >/dev/null 2>&1 || true

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ssh-keyscan -p "$port" 127.0.0.1 > known_hosts 2>/dev/null && [ -s known_hosts ]; then
    echo "Ready on 127.0.0.1:$port. Now run: conn3x init && conn3x apply -var port=$port"
    exit 0
  fi
  sleep 1
done
echo "The container started, but SSH didn't answer on 127.0.0.1:$port." >&2
exit 1
