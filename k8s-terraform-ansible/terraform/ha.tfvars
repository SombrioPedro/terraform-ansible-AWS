# Extra 4 — Alta disponibilidade
# Uso: terraform apply -var-file=terraform.tfvars -var-file=ha.tfvars
#
# ATENÇÃO: com etcd "stacked", 2 Control Planes NÃO toleram a perda de nenhum
# (quorum do etcd com 2 membros = 2). Para tolerar 1 falha, use 3.

control_plane_count = 2
worker_count        = 3
