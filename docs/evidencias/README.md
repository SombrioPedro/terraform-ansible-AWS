# Evidências

Coloque aqui os prints/logs da execução. Checklist exigido pelo desafio:

- [ ] `terraform apply` (print do final com os outputs) → `terraform-apply.png` ou `.log`
- [ ] `ansible-playbook` (print do PLAY RECAP sem `failed`) → `ansible-playbook.png` ou `.log`
- [ ] `kubectl get nodes` (todos `Ready`)
- [ ] `kubectl get pods -A` (Calico e componentes do kube-system `Running`)
- [ ] `kubectl get svc` (Service `nginx` NodePort `80:30080`)
- [ ] NGINX no navegador em `http://IP_PUBLICO_DO_WORKER:30080`
- [ ] `terraform destroy` + console da AWS sem recursos do projeto

Dicas para gerar logs:

```bash
terraform -chdir=terraform apply 2>&1 | tee docs/evidencias/terraform-apply.log
./scripts/validar-cluster.sh     # gera docs/evidencias/validacao-<data>.log
```
