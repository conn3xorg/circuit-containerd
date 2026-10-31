# circuit-containerd

A Conn3x circuit that installs containerd the way its getting-started guide lays it out: the official release tarball, runc and the CNI plugins, each at a version you pin and each checked against its release's SHA-256, plus upstream's systemd unit and a `config.toml` you control. It's for hosts that run containers without Docker, such as a Kubernetes node you're assembling yourself, where you'd like every machine on the same containerd whatever its distribution ships.

The defaults are containerd 2.4.2, runc 1.5.2 and CNI plugins 1.9.1.

## If Docker is already there

Docker's `containerd.io` package brings its own containerd, with the same service name, socket and config file. So does a distribution's `containerd` package. Installing over either would pull the runtime out from under whatever is using it, so the circuit's first step looks for them and stops the apply with a message naming what it found:

```text
Error: command failed with exit status 1: Found /usr/bin/containerd /usr/bin/dockerd on this host: Docker or a distribution package already provides containerd. [...]
```

It looks for `containerd` in `/usr/bin` and `/usr/sbin`, `dockerd` in `/usr/bin`, `/usr/sbin` and `/usr/local/bin`, and `/snap/bin/docker`. Install Docker after this circuit and the next plan shows that step again, and the next apply stops there.

Pick one per host: this circuit, or [circuit-docker](https://github.com/conn3xorg/circuit-docker). [circuit-kubeadm](https://github.com/conn3xorg/circuit-kubeadm) installs `containerd.io` itself, so it doesn't go with this one either.

## Usage

```hcl
module "containerd" {
  source = "github.com/conn3xorg/circuit-containerd?ref=v0.1.0"

  hosts                = { node1 = "203.0.113.10", node2 = "203.0.113.11" }
  ssh_private_key_file = "~/.ssh/id_ed25519"
}
```

Then run `conn3x init` and `conn3x apply`. A second `conn3x plan` says `No changes.` On the host:

```sh
ctr image pull ghcr.io/containerd/busybox:1.36
ctr run --rm ghcr.io/containerd/busybox:1.36 hello echo hello
```

For hosts created in the same plan, pass host objects with the host key you generated, so Conn3x checks it without a known_hosts entry:

```hcl
hosts = {
  for name, d in digitalocean_droplet.node : name => {
    address  = d.ipv4_address
    host_key = tls_private_key.host[name].public_key_openssh
  }
}
```

To try it on a throwaway container first, see [examples/local](examples/local).

### Changing a release

Each version moves with its checksums, which come from the files beside the release: `.sha256sum` for containerd, `runc.sha256sum` for runc and `.sha256` for the CNI plugins.

```hcl
containerd_version = "2.4.1"
containerd_checksums = {
  amd64 = "<SHA-256 of containerd-2.4.1-linux-amd64.tar.gz>"
  arm64 = "<SHA-256 of containerd-2.4.1-linux-arm64.tar.gz>"
}
```

A new containerd restarts the service. Running containers carry on through that, since each has its own shim and upstream's unit sets `KillMode=process`. A file that doesn't match its checksum fails the apply before anything is unpacked.

### The config file

`config_toml` becomes `/etc/containerd/config.toml`, and containerd fills in its defaults for anything you leave out. The default sets only the `systemd` cgroup driver for runc, which [containerd's CRI docs](https://github.com/containerd/containerd/blob/main/docs/cri/config.md) describe for Kubernetes:

```toml
version = 3

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  SystemdCgroup = true
```

Your text goes to `config.toml.conn3x` first. Only once `containerd config dump` can read it does it replace the live file and restart the service, so a typo fails the apply and the daemon keeps running on its old config. `version = 3` is the format for containerd 2.x, so going back to a 1.x release means changing this too.

The text is stored in state. Keep registry passwords out of it.

## What it does

On each host, in order:

1. Stops if Docker's or a distribution's containerd is there.
2. Installs `curl`, `tar` and `gzip`.
3. Downloads the containerd tarball to `/opt/containerd`, keeping it only if its SHA-256 matches, and unpacks it under `/usr/local`, unless that release is already there.
4. Downloads runc to `/usr/local/sbin/runc`, checked the same way.
5. Downloads the CNI plugins tarball to `/opt/containerd`, checked the same way, and unpacks it to `/opt/cni/bin`.
6. Writes `/etc/containerd/config.toml`, as above.
7. Writes upstream's unit to `/usr/local/lib/systemd/system/containerd.service`. A copy from the v2.4.2 tag lives in this repository's `files/`, so it can't change under a pinned module version.
8. Starts and enables `containerd`, restarting it if the release, config or unit changed.

Before the circuit runs, the `conn3x_host` data source reads each host's architecture over SSH, which picks the release files.

### What it doesn't do

- It doesn't write a CNI network. The plugins are installed, but `ctr run --cni` and Kubernetes need a config in `/etc/cni/net.d`, which is yours or your cluster's to choose.
- It doesn't set up what Kubernetes wants beyond the cgroup driver, such as `br_netfilter` or IP forwarding.
- It doesn't install `nerdctl`, a registry mirror or image credentials.
- It doesn't uninstall anything. Deleting the module leaves the files and the service in place.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `hosts` | any | Required | Hosts to configure, by name. Each value is an address, such as `"203.0.113.10"`, or a host object such as `{ address = "203.0.113.10", host_key = "ssh-ed25519 AAAA..." }`. A host object can also set `user`, `port`, `private_key_file` and `jump_hosts`. The two forms can be mixed. |
| `ssh_user` | string | `"root"` | User to log in as. |
| `ssh_port` | number | `22` | SSH port. |
| `ssh_private_key_file` | string | `null` | Path to a private key. When null, Conn3x uses the SSH agent. |
| `ssh_known_hosts_file` | string | `null` | known_hosts file to check host keys against. When null, `~/.ssh/known_hosts`. Not used for a host object with `host_key`. |
| `ssh_become` | bool | `false` | Run commands as root through sudo. Set it when `ssh_user` isn't root. |
| `containerd_version` | string | `"2.4.2"` | containerd release to install. Change `containerd_checksums` with it. |
| `containerd_checksums` | map(string) | The tarballs of 2.4.2 | SHA-256 of the `amd64` and `arm64` tarballs. |
| `runc_version` | string | `"1.5.2"` | runc release to install. Change `runc_checksums` with it. |
| `runc_checksums` | map(string) | The binaries of 1.5.2 | SHA-256 of the `amd64` and `arm64` binaries. |
| `cni_version` | string | `"1.9.1"` | CNI plugins release to install. Change `cni_checksums` with it. |
| `cni_checksums` | map(string) | The tarballs of 1.9.1 | SHA-256 of the `amd64` and `arm64` tarballs. |
| `config_toml` | string | The systemd cgroup driver | Contents of `/etc/containerd/config.toml`. Stored in state. |

## Outputs

| Name | Description |
| --- | --- |
| `socket` | Path of containerd's socket on each host: `/run/containerd/containerd.sock`. |

## Requirements

Requires Conn3x v0.6.10 or later, systemd, and hosts with outbound HTTPS to github.com. amd64 and arm64, on glibc: upstream's containerd binary may not work on musl distributions such as Alpine.

## Tested on

Rocky Linux 10, Fedora 45, Ubuntu 24.04 and Debian 13. [examples/local](examples/local) was applied to each on arm64, in a privileged container with `/var/lib/containerd` on a volume, and the second plan had no changes. On each, `containerd` was active and enabled, `ctr` reported 2.4.2 for client and server, runc and the CNI `bridge` plugin reported their pinned versions, the CRI plugin loaded, and `ctr` pulled `ghcr.io/containerd/busybox:1.36` and ran it. On Rocky Linux 10, a config with a TOML error failed the apply and left the live file and the service alone, and a valid change restarted the service. CI runs the apply, the second plan and the `ctr` check on amd64 across the four distributions.

A container can't cover everything, so these ran on droplets: an Ubuntu 24.04 and a Rocky Linux 10 with SELinux enforcing, both `s-1vcpu-1gb`, amd64. The same checks passed. With a bridge network written by hand in `/etc/cni/net.d`, `ctr run --cni` got an address from `host-local` and pinged its gateway, so the plugins work. A running container stayed up through moving containerd to 2.4.1 and back, with the daemon on the new release each time. After a reboot, containerd was running with the `overlay` module loaded, `ctr` ran a container, and the plan had no changes.

On a Debian 13 droplet with `docker-ce` from Docker's repository and a container running, the apply stopped at the first step with the message above. `/usr/local/bin/containerd` and `runc` weren't installed, Docker's `config.toml` and unit kept their checksums, and the container kept running. On a Debian 13 container already set up by this circuit, installing the distribution's `containerd` package made the next plan show the first step again, and the next apply stopped there.

Fedora 45 ran in a container only, as DigitalOcean has no image of it. Neither a Kubernetes cluster nor `ssh_become` was exercised: every test logged in as root and used `ctr`.

## License

MPL-2.0. See [LICENSE](LICENSE). containerd, runc and the CNI plugins are under the Apache License 2.0, and `files/containerd.service` is copied from containerd unchanged.
