# Local example

Applies circuit-containerd to a throwaway Rocky Linux 10 container with systemd, installing containerd 2.4.2, runc 1.5.2 and the CNI plugins 1.9.1. You need Conn3x and rootful Podman: on a Mac, `export CONTAINER_CONNECTION=podman-machine-default-root`; on Linux, `export PODMAN="sudo podman"`.

```sh
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To see it working:

```sh
ssh -p 2312 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 'ctr image pull ghcr.io/containerd/busybox:1.36 && ctr run --rm ghcr.io/containerd/busybox:1.36 hello echo hello'
```

`up.sh` listens on `127.0.0.1:2312`, with a privileged container and `/var/lib/containerd` on a volume, where containerd can use overlayfs. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` stops the container, which removes it and its volumes, then removes the key and the state.
