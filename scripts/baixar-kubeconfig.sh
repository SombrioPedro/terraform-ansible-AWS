#!/usr/bin/env bash
# Copia o kubeconfig do Control Plane para a sua máquina, apontando
# para o IP público do Control Plane (que está nos certSANs e liberado
# no Security Group somente para o seu IP).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/terraform"
KEY="$(ls "$ROOT"/keys/*.pem | head -n1)"
BASTION="$(terraform -chdir="$TF" output -raw bastion_public_ip)"
CP_PRIV="$(terraform -chdir="$TF" output -raw control_plane_private_ip)"
CP_PUB="$(terraform -chdir="$TF" output -raw control_plane_public_ip)"
DEST="$ROOT/keys/kubeconfig"

SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
if [[ -n "$BASTION" ]]; then
  TARGET=(-o "ProxyCommand=ssh ${SSH_OPTS[*]} -W %h:%p ubuntu@$BASTION" "ubuntu@$CP_PRIV")
else
  TARGET=("ubuntu@$CP_PUB")
fi

ssh "${SSH_OPTS[@]}" "${TARGET[@]}" "cat ~/.kube/config" \
  | sed -E "s#server: https://[^:]+:6443#server: https://$CP_PUB:6443#" > "$DEST"
chmod 600 "$DEST"

echo "Kubeconfig salvo em $DEST (ignorado pelo Git)."
echo "Use: export KUBECONFIG=$DEST && kubectl get nodes"
