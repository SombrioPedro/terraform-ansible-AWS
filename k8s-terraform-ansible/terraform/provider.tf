provider "aws" {
  region = var.aws_region

  # As credenciais NÃO ficam aqui: use `aws configure`, AWS_PROFILE
  # ou as variáveis AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
