data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Os nós ficam em subnets públicas (com IP público) para:
#  - baixar pacotes sem precisar de NAT Gateway (que é pago por hora);
#  - permitir o acesso ao NodePort via http://IP_PUBLICO_DO_WORKER:30080.
# O SSH direto da Internet é bloqueado pelo Security Group quando o Bastion está ativo.

resource "aws_subnet" "control_plane" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.control_plane_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-control-plane"
  }
}

resource "aws_subnet" "workers" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.workers_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-workers"
  }
}

resource "aws_subnet" "bastion" {
  count = var.enable_bastion ? 1 : 0

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.bastion_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-bastion"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt-public"
  }
}

resource "aws_route_table_association" "control_plane" {
  subnet_id      = aws_subnet.control_plane.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "workers" {
  subnet_id      = aws_subnet.workers.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "bastion" {
  count = var.enable_bastion ? 1 : 0

  subnet_id      = aws_subnet.bastion[0].id
  route_table_id = aws_route_table.public.id
}
