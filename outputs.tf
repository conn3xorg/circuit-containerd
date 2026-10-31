output "socket" {
  description = "Path of containerd's socket on each host, for clients such as ctr and the kubelet."
  value       = local.socket
}
