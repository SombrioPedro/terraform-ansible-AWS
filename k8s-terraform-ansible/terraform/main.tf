# ======================================================================
# Locals
# ======================================================================

# Detecta automaticamente o IP público de quem roda o Terraform
# (usado quando my_ip_cidr não é informado no terraform.tfvars).
data "http" "my_ip" {
  count = var.my_ip_cidr == "" ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

locals {
  my_ip_cidr = var.my_ip_cidr != "" ? var.my_ip_cidr : "${chomp(try(data.http.my_ip[0].response_body, "0.0.0.0"))}/32"

  ha_enabled = var.control_plane_count > 1

  control_plane_names = [
    for i in range(var.control_plane_count) :
    var.control_plane_count == 1 ? "k8s-control-plane" : "k8s-control-plane-${i + 1}"
  ]

  private_key_path = abspath("${path.module}/../keys/${var.project_name}-key.pem")

  # Endpoint compartilhado da API: NLB no modo HA, IP privado do CP no modo simples
  api_endpoint = local.ha_enabled ? one(aws_lb.api[*].dns_name) : aws_instance.control_plane[0].private_ip

  bastion_public_ip = try(aws_instance.bastion[0].public_ip, "")
}

# ======================================================================
# Extra 4 — Endpoint compartilhado dos API Servers (Network Load Balancer)
# ======================================================================

resource "aws_lb" "api" {
  count = local.ha_enabled ? 1 : 0

  name                             = "${var.project_name}-api"
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = [aws_subnet.control_plane.id, aws_subnet.workers.id]
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-api-nlb"
  }
}

resource "aws_lb_target_group" "api" {
  count = local.ha_enabled ? 1 : 0

  name        = "${var.project_name}-api-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  # Sem isso, quando um Control Plane acessa o NLB e o NLB manda a conexão
  # para ele mesmo (hairpin), o pacote é descartado e o kubeadm trava.
  preserve_client_ip = "false"

  deregistration_delay = 30

  health_check {
    protocol            = "TCP"
    port                = "6443"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "api" {
  count = local.ha_enabled ? var.control_plane_count : 0

  target_group_arn = aws_lb_target_group.api[0].arn
  target_id        = aws_instance.control_plane[count.index].id
  port             = 6443
}

resource "aws_lb_listener" "api" {
  count = local.ha_enabled ? 1 : 0

  load_balancer_arn = aws_lb.api[0].arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[0].arn
  }
}

# ======================================================================
# Extra 2 — Inventory do Ansible gerado automaticamente
# ======================================================================

resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventory.tpl", {
    control_planes = [
      for i, inst in aws_instance.control_plane : {
        name       = local.control_plane_names[i]
        public_ip  = inst.public_ip
        private_ip = inst.private_ip
      }
    ]
    workers = [
      for i, inst in aws_instance.worker : {
        name       = "k8s-worker-${i + 1}"
        public_ip  = inst.public_ip
        private_ip = inst.private_ip
      }
    ]
    use_bastion  = var.enable_bastion
    bastion_ip   = local.bastion_public_ip
    key_path     = local.private_key_path
    api_endpoint = local.api_endpoint
  })
}

# ======================================================================
# Extra 1 — Terraform executando o Ansible
# ======================================================================

resource "terraform_data" "ansible" {
  count = var.run_ansible ? 1 : 0

  # Roda de novo sempre que uma máquina for recriada ou o inventory mudar
  triggers_replace = {
    control_planes = aws_instance.control_plane[*].id
    workers        = aws_instance.worker[*].id
    inventory      = local_file.inventory.content
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../ansible"
    command     = "ansible-playbook -i inventory.ini site.yml"

    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_FORCE_COLOR       = "1"
    }
  }

  depends_on = [
    local_sensitive_file.private_key,
    aws_route_table_association.control_plane,
    aws_route_table_association.workers,
    aws_route_table_association.bastion,
    aws_vpc_security_group_ingress_rule.ssh_from_bastion,
    aws_vpc_security_group_ingress_rule.ssh_from_my_ip,
    aws_vpc_security_group_ingress_rule.bastion_ssh,
    aws_vpc_security_group_ingress_rule.self,
    aws_vpc_security_group_ingress_rule.api_from_vpc,
    aws_vpc_security_group_egress_rule.cluster_all,
    aws_vpc_security_group_egress_rule.bastion_all,
    aws_lb_listener.api,
    aws_lb_target_group_attachment.api,
  ]
}
