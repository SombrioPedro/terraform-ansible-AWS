# Nenhum segredo aqui: credenciais AWS ficam no `aws configure` / AWS_PROFILE.

aws_region   = "us-east-1"
project_name = "k8s-lab"

# Deixe vazio para detectar seu IP automaticamente, ou fixe: "200.100.50.25/32"
my_ip_cidr = ""

instance_type = "t3.small"

# Topologia do desafio principal
control_plane_count = 1
worker_count        = 2

# Extras
enable_bastion = true # Extra 3
run_ansible    = true # Extra 1

nginx_public_access = true