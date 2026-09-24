output "control_plane_public_ip" {
  description = "IP público do Control Plane (primário)"
  value       = aws_instance.control_plane[0].public_ip
}

output "control_plane_private_ip" {
  description = "IP privado do Control Plane (primário)"
  value       = aws_instance.control_plane[0].private_ip
}

output "control_plane_public_ips" {
  description = "IPs públicos de todos os Control Planes"
  value       = aws_instance.control_plane[*].public_ip
}

output "control_plane_private_ips" {
  description = "IPs privados de todos os Control Planes"
  value       = aws_instance.control_plane[*].private_ip
}

output "worker_public_ips" {
  description = "IPs públicos dos Workers"
  value       = aws_instance.worker[*].public_ip
}

output "worker_private_ips" {
  description = "IPs privados dos Workers"
  value       = aws_instance.worker[*].private_ip
}

output "bastion_public_ip" {
  description = "IP público do Bastion Host (vazio se desativado)"
  value       = local.bastion_public_ip
}

output "api_endpoint" {
  description = "Endpoint da API do Kubernetes (NLB no modo HA)"
  value       = "${local.api_endpoint}:6443"
}

output "allowed_ip" {
  description = "IP liberado no Security Group para SSH/API/NodePort"
  value       = local.my_ip_cidr
}

output "ssh_control_plane" {
  description = "Comando para acessar o Control Plane"
  value = var.enable_bastion ? (
    "ssh -i ${local.private_key_path} -J ubuntu@${local.bastion_public_ip} ubuntu@${aws_instance.control_plane[0].private_ip}"
    ) : (
    "ssh -i ${local.private_key_path} ubuntu@${aws_instance.control_plane[0].public_ip}"
  )
}

output "nginx_urls" {
  description = "URLs do NGINX via NodePort"
  value       = [for ip in aws_instance.worker[*].public_ip : "http://${ip}:30080"]
}
