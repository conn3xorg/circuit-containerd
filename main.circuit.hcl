# Facts give each host's architecture, which picks the release files.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = contains(keys(local.go_arch), self.arch)
      error_message = "Host ${each.key} is ${self.arch}. This circuit installs the amd64 and arm64 builds."
    }
  }
}

locals {
  go_arch = { x86_64 = "amd64", aarch64 = "arm64" }
  arch    = { for name in keys(var.hosts) : name => lookup(local.go_arch, data.conn3x_host.facts[name].arch, data.conn3x_host.facts[name].arch) }

  downloads = "/opt/containerd"
  socket    = "/run/containerd/containerd.sock"
  candidate = "/etc/containerd/config.toml.conn3x"

  # What Docker's containerd.io and docker-ce packages, a distribution's
  # containerd package, and Docker's static and snap installs leave behind.
  # This circuit's own files are all elsewhere, so it never trips on itself.
  conflicts = "/usr/bin/containerd /usr/sbin/containerd /usr/bin/dockerd /usr/sbin/dockerd /usr/local/bin/dockerd /snap/bin/docker"
}

circuit "containerd" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Those installs want the same service name, socket and config file, so
  # carrying on would take containerd away from Docker's containers. This
  # comes first, and a failed step stops the circuit before anything changes.
  step "no_conflict" {
    command {
      command = "echo \"Found $(ls -d ${local.conflicts} 2>/dev/null | tr '\\n' ' ')on this host: Docker or a distribution package already provides containerd. This circuit would fight it for the containerd service, its socket and its config file, so it changed nothing. Remove that install first, or use circuit-docker and leave this circuit out.\" >&2; exit 1"
      unless  = "[ -z \"$(ls -d ${local.conflicts} 2>/dev/null)\" ]"
    }
  }

  step "tool" {
    for_each = ["curl", "tar", "gzip"]
    package {
      name = item.value
    }
  }

  # Each download step keeps its file only if it matches the checksum, which
  # comes from the release's own checksum files.
  step "containerd_tarball" {
    download {
      url    = "https://github.com/containerd/containerd/releases/download/v${var.containerd_version}/containerd-${var.containerd_version}-linux-${local.arch[each.key]}.tar.gz"
      sha256 = var.containerd_checksums[local.arch[each.key]]
      dest   = "${local.downloads}/containerd-${var.containerd_version}-linux-${local.arch[each.key]}.tar.gz"
    }
  }

  # An archive step wouldn't do for the next two: its creates path is the
  # same before and after a new release, so it would never unpack that one.
  step "containerd" {
    command {
      command = "tar -C /usr/local -xzf ${local.downloads}/containerd-${var.containerd_version}-linux-${local.arch[each.key]}.tar.gz"
      unless  = "/usr/local/bin/containerd --version 2>/dev/null | grep -qF ' v${var.containerd_version} '"
    }
    notify = [handler.restart]
  }

  step "runc" {
    download {
      url    = "https://github.com/opencontainers/runc/releases/download/v${var.runc_version}/runc.${local.arch[each.key]}"
      sha256 = var.runc_checksums[local.arch[each.key]]
      dest   = "/usr/local/sbin/runc"
      mode   = "0755"
    }
  }

  step "cni_tarball" {
    download {
      url    = "https://github.com/containernetworking/plugins/releases/download/v${var.cni_version}/cni-plugins-linux-${local.arch[each.key]}-v${var.cni_version}.tgz"
      sha256 = var.cni_checksums[local.arch[each.key]]
      dest   = "${local.downloads}/cni-plugins-linux-${local.arch[each.key]}-v${var.cni_version}.tgz"
    }
  }

  step "cni_dir" {
    directory {
      path = "/opt/cni/bin"
    }
  }

  step "cni" {
    command {
      command = "tar -C /opt/cni/bin -xzf ${local.downloads}/cni-plugins-linux-${local.arch[each.key]}-v${var.cni_version}.tgz"
      unless  = "/opt/cni/bin/bridge 2>&1 | grep -qF ' v${var.cni_version}'"
    }
  }

  step "config_dir" {
    directory {
      path = "/etc/containerd"
    }
  }

  # The rendered config lands beside the live one first.
  step "candidate" {
    file {
      path    = local.candidate
      content = var.config_toml
    }
  }

  # Copies the candidate over the live config only once containerd itself
  # can read it, so a typo fails here and the running daemon keeps its
  # config. The plan checks unless before the candidate is written, so
  # triggers makes the apply check it again once it is.
  step "config" {
    command {
      command  = "/usr/local/bin/containerd --config ${local.candidate} config dump >/dev/null && cp ${local.candidate} /etc/containerd/config.toml"
      unless   = "[ \"$(sha256sum < ${local.candidate})\" = \"$(sha256sum < /etc/containerd/config.toml)\" ]"
      triggers = { config = sha256(var.config_toml) }
    }
    notify = [handler.restart]
  }

  # Upstream's unit from the release tag, kept in this repository rather
  # than fetched, so it's reviewed here and can't change under a pinned
  # module version.
  step "unit" {
    file {
      path    = "/usr/local/lib/systemd/system/containerd.service"
      content = file("${path.module}/files/containerd.service")
    }
    notify = [handler.restart]
  }

  step "running" {
    service {
      name    = "containerd"
      state   = "started"
      enabled = true
    }
  }

  # Containers keep running through this: upstream's unit has
  # KillMode=process, and each container has its own shim.
  handler "restart" {
    service {
      name = "containerd"
    }
  }
}
