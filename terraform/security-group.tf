# ======================================================================
# Security Group do cluster (Control Planes + Workers)
# ======================================================================

resource "aws_security_group" "cluster" {
  name        = "${var.project_name}-cluster-sg"
  description = "Nos do cluster Kubernetes"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-cluster-sg"
  }
}

# SSH: vindo do Bastion (Extra 3) ou, sem Bastion, apenas do seu IP
resource "aws_vpc_security_group_ingress_rule" "ssh_from_bastion" {
  count = var.enable_bastion ? 1 : 0

  security_group_id            = aws_security_group.cluster.id
  description                  = "SSH somente a partir do Bastion"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion[0].id
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_my_ip" {
  count = var.enable_bastion ? 0 : 1

  security_group_id = aws_security_group.cluster.id
  description       = "SSH somente a partir do IP do aluno"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = local.my_ip_cidr
}

# Kubernetes API Server
resource "aws_vpc_security_group_ingress_rule" "api_from_my_ip" {
  security_group_id = aws_security_group.cluster.id
  description       = "Kubernetes API a partir do IP do aluno"
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_ipv4         = local.my_ip_cidr
}

# Necessária para o NLB do modo HA: com preserve_client_ip = false,
# o tráfego chega aos targets com o IP privado do NLB (dentro da VPC).
resource "aws_vpc_security_group_ingress_rule" "api_from_vpc" {
  security_group_id = aws_security_group.cluster.id
  description       = "Kubernetes API dentro da VPC (NLB e nos)"
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_ipv4         = var.vpc_cidr
}

# Kubelet
resource "aws_vpc_security_group_ingress_rule" "kubelet" {
  security_group_id = aws_security_group.cluster.id
  description       = "Kubelet API"
  ip_protocol       = "tcp"
  from_port         = 10250
  to_port           = 10250
  cidr_ipv4         = var.vpc_cidr
}

# NodePort (NGINX em 30080)
resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  security_group_id = aws_security_group.cluster.id
  description       = "NodePort Services"
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
  cidr_ipv4         = "0.0.0.0/0"
}

# Acesso público só ao NGINX (a porta precisa bater com nginx_node_port do Ansible)
resource "aws_vpc_security_group_ingress_rule" "nginx_public" {
  count = var.nginx_public_access ? 1 : 0

  security_group_id = aws_security_group.cluster.id
  description       = "NGINX NodePort aberto para a Internet"
  ip_protocol       = "tcp"
  from_port         = 30080
  to_port           = 30080
  cidr_ipv4         = "0.0.0.0/0"
}

# Comunicação livre entre os nós (etcd, kube-proxy, Calico BGP 179 e IP-in-IP protocolo 4)
resource "aws_vpc_security_group_ingress_rule" "self" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "Todo trafego entre os nos do cluster"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.cluster.id
}

resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.cluster.id
  description       = "Saida liberada (pacotes, imagens)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ======================================================================
# Security Group do Bastion (Extra 3)
# ======================================================================

resource "aws_security_group" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name        = "${var.project_name}-bastion-sg"
  description = "Bastion Host"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  description       = "SSH somente a partir do IP do aluno"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = local.my_ip_cidr
}

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  description       = "Saida liberada"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
