#!/usr/bin/env bash
# Executa os testes obrigatórios do Kubernetes e da aplicação e salva
# a saída em docs/evidencias/ (serve como evidência para a entrega).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="$ROOT/terraform"
OUT_DIR="$ROOT/docs/evidencias"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$OUT_DIR/validacao-$STAMP.log"

KEY="$(ls "$ROOT"/keys/*.pem | head -n1)"
BASTION="$(terraform -chdir="$TF" output -raw bastion_public_ip)"
CP_PRIV="$(terraform -chdir="$TF" output -raw control_plane_private_ip)"
CP_PUB="$(terraform -chdir="$TF" output -raw control_plane_public_ip)"
WORKERS="$(terraform -chdir="$TF" output -json worker_public_ips | tr -d '[]" ' | tr ',' ' ')"

SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
if [[ -n "$BASTION" ]]; then
  TARGET=(-o "ProxyCommand=ssh ${SSH_OPTS[*]} -W %h:%p ubuntu@$BASTION" "ubuntu@$CP_PRIV")
else
  TARGET=("ubuntu@$CP_PUB")
fi

run() {
  echo
  echo "\$ $*"
  ssh "${SSH_OPTS[@]}" "${TARGET[@]}" "$*"
}

mkdir -p "$OUT_DIR"
{
  echo "Validação do cluster - $(date)"
  run kubectl get nodes -o wide
  run kubectl get pods -A -o wide
  run kubectl get svc -A
  run kubectl get deployment
  run kubectl get pods -o wide
  run kubectl get svc

  echo
  echo "### Teste HTTP do NGINX via NodePort"
  for ip in $WORKERS; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$ip:30080" || true)"
    echo "http://$ip:30080 -> HTTP $code"
  done
} 2>&1 | tee "$LOG"

echo
echo "Evidência salva em: $LOG"
