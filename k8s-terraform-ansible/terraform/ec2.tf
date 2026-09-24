# Ubuntu 24.04 LTS oficial da Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------- Key Pair
# A chave é gerada pelo Terraform e salva em ../keys (ignorada pelo Git).

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "cluster" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = local.private_key_path
  file_permission = "0600"
}

# ---------------------------------------------------------------- Control Plane(s)

resource "aws_instance" "control_plane" {
  count = var.control_plane_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.control_plane.id
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = aws_key_pair.cluster.key_name
  source_dest_check      = false

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = local.control_plane_names[count.index]
    Role = "control-plane"
  }
}

# ---------------------------------------------------------------- Workers

resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.workers.id
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = aws_key_pair.cluster.key_name
  source_dest_check      = false

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "k8s-worker-${count.index + 1}"
    Role = "worker"
  }
}

# ---------------------------------------------------------------- Bastion (Extra 3)

resource "aws_instance" "bastion" {
  count = var.enable_bastion ? 1 : 0

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.bastion[0].id
  vpc_security_group_ids = [aws_security_group.bastion[0].id]
  key_name               = aws_key_pair.cluster.key_name

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "k8s-bastion"
    Role = "bastion"
  }
}
