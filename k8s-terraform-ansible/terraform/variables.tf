variable "aws_region" {
  description = "Região AWS onde o cluster será criado"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefixo usado no nome dos recursos"
  type        = string
  default     = "pedros"
}

# ---------------------------------------------------------------- Rede

variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "control_plane_subnet_cidr" {
  description = "Subnet do(s) Control Plane(s)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "workers_subnet_cidr" {
  description = "Subnet dos Workers"
  type        = string
  default     = "10.0.2.0/24"
}

variable "bastion_subnet_cidr" {
  description = "Subnet do Bastion Host (Extra 3)"
  type        = string
  default     = "10.0.3.0/24"
}

variable "my_ip_cidr" {
  description = "Seu IP público em CIDR (ex.: 200.100.50.25/32). Deixe vazio para detectar automaticamente."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------- EC2

variable "instance_type" {
  description = "Tipo de instância dos nós do cluster (kubeadm exige no mínimo 2 vCPU e ~1.7 GB de RAM)"
  type        = string
  default     = "t3.small"
}

variable "bastion_instance_type" {
  description = "Tipo de instância do Bastion"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Tamanho do disco (GB) dos nós"
  type        = number
  default     = 20
}

variable "control_plane_count" {
  description = "Quantidade de Control Planes. Acima de 1 ativa o modo HA com NLB (Extra 4)."
  type        = number
  default     = 1

  validation {
    condition     = var.control_plane_count >= 1
    error_message = "É necessário pelo menos 1 Control Plane."
  }
}

variable "worker_count" {
  description = "Quantidade de Workers"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1
    error_message = "É necessário pelo menos 1 Worker."
  }
}

# ---------------------------------------------------------------- Extras

variable "enable_bastion" {
  description = "Cria o Bastion Host e bloqueia SSH direto da Internet nos nós (Extra 3)"
  type        = bool
  default     = true
}

variable "run_ansible" {
  description = "Executa o ansible-playbook automaticamente no terraform apply (Extra 1)"
  type        = bool
  default     = true
}

variable "nginx_public_access" {
  description = "Libera a porta 30080 (NGINX) para qualquer IP, ex.: acesso pelo celular"
  type        = bool
  default     = false
}