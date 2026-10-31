variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "containerd_version" {
  type        = string
  default     = "2.4.2"
  description = "containerd release to install, such as \"2.4.2\". Change containerd_checksums with it."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.containerd_version))
    error_message = "containerd_version must look like \"2.4.2\", without a leading v."
  }
}

variable "containerd_checksums" {
  type        = map(string)
  description = "SHA-256 of the amd64 and arm64 containerd tarballs, from the release's .sha256sum files. Change these with containerd_version."
  default = {
    amd64 = "35880c1dd4627e8ce56526bfabb39c144e83458ffdb197ce6f05d17d94d7d91e"
    arm64 = "fdfab81a86192ddb8165d72f116ec985485c9e12505e323c4f4579c48020f276"
  }

  validation {
    condition     = alltrue([for c in values(var.containerd_checksums) : can(regex("^[0-9a-f]{64}$", c))])
    error_message = "Each of containerd_checksums must be a SHA-256 in lowercase hex."
  }
}

variable "runc_version" {
  type        = string
  default     = "1.5.2"
  description = "runc release to install, such as \"1.5.2\". Change runc_checksums with it."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.runc_version))
    error_message = "runc_version must look like \"1.5.2\", without a leading v."
  }
}

variable "runc_checksums" {
  type        = map(string)
  description = "SHA-256 of the runc.amd64 and runc.arm64 binaries, from the release's runc.sha256sum. Change these with runc_version."
  default = {
    amd64 = "599f6f94ff8c5057241eff0d54c3c74f95c34935b6457b33fe545defc61e9488"
    arm64 = "d10ecae898361832a059be2089bab92d158aec54661b18ed7346ed79628b46b0"
  }

  validation {
    condition     = alltrue([for c in values(var.runc_checksums) : can(regex("^[0-9a-f]{64}$", c))])
    error_message = "Each of runc_checksums must be a SHA-256 in lowercase hex."
  }
}

variable "cni_version" {
  type        = string
  default     = "1.9.1"
  description = "CNI plugins release to install, such as \"1.9.1\". Change cni_checksums with it."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.cni_version))
    error_message = "cni_version must look like \"1.9.1\", without a leading v."
  }
}

variable "cni_checksums" {
  type        = map(string)
  description = "SHA-256 of the amd64 and arm64 CNI plugin tarballs, from the release's .sha256 files. Change these with cni_version."
  default = {
    amd64 = "b98f74a0f8522f0a83867178729c1aa70f2158f90c45a2ca8fa791db1c76b303"
    arm64 = "56171987d3947707c3563db2f4001bccaf50fd63468611b9f3cbecb1375ee7ec"
  }

  validation {
    condition     = alltrue([for c in values(var.cni_checksums) : can(regex("^[0-9a-f]{64}$", c))])
    error_message = "Each of cni_checksums must be a SHA-256 in lowercase hex."
  }
}

variable "config_toml" {
  type        = string
  description = "Contents of /etc/containerd/config.toml. containerd fills in its defaults for anything this leaves out. It's stored in state, so keep registry passwords out of it."
  default     = <<-EOT
    version = 3

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
      SystemdCgroup = true
  EOT
}
