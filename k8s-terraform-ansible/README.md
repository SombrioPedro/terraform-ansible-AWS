# Cluster Kubernetes na AWS com Terraform + Ansible

Cluster Kubernetes criado **sem EKS**: o Terraform cria a infraestrutura na AWS e o Ansible
configura os servidores (containerd, kubeadm, kubelet, kubectl, Calico) e publica um NGINX.

Todos os desafios extras estão implementados:

| Extra | Como foi feito |
|---|---|
| 1 — Terraform executando Ansible | `terraform_data` + `provisioner "local-exec"` em `terraform/main.tf` |
| 2 — Inventory automático | `templatefile()` + `local_file` geram `ansible/inventory.ini` |
| 3 — Bastion Host | EC2 `k8s-bastion`; os nós só aceitam SSH vindo do SG do Bastion |
| 4 — Alta disponibilidade | `ha.tfvars` (2 CPs + 3 Workers) com NLB interno como endpoint da API |

---

## 1. Arquitetura

```text
                          Internet
                             │
                    ┌────────┴────────┐
                    │ Internet Gateway│
                    └────────┬────────┘
┌───────────────────── VPC 10.0.0.0/16 ─────────────────────────────┐
│                                                                   │
│  Subnet Bastion 10.0.3.0/24      Subnet Control Plane 10.0.1.0/24 │
│  ┌──────────────┐  SSH           ┌───────────────────┐            │
│  │ k8s-bastion  │───────────────▶│ k8s-control-plane │            │
│  └──────────────┘        │       └─────────┬─────────┘            │
│                          │                 │ Calico (IP-in-IP)    │
│                          │  Subnet Workers 10.0.2.0/24            │
│                          │       ┌─────────┴─────────┐            │
│                          └──────▶│ k8s-worker-1      │◀── :30080  │
│                                  │ k8s-worker-2      │◀── :30080  │
│                                  └───────────────────┘            │
└───────────────────────────────────────────────────────────────────┘
```

Diagramas completos (incluindo o modo HA) em [`docs/arquitetura.md`](docs/arquitetura.md).

**Decisões de projeto**

- Os nós ficam em subnets públicas com IP público para baixar pacotes sem NAT Gateway (que é
  cobrado por hora) e para o NGINX responder em `http://IP_PUBLICO_DO_WORKER:30080`.
  Mesmo assim, **nenhum nó aceita SSH da Internet**: a regra de SSH do Security Group do cluster
  tem como origem apenas o Security Group do Bastion.
- SSH (Bastion), API 6443 e NodePort só ficam abertos para o **seu IP** (detectado
  automaticamente ou informado em `my_ip_cidr`).
- Tráfego entre os nós é liberado usando o próprio Security Group como origem (inclui o
  protocolo IP-in-IP que o Calico usa por padrão).
- A chave SSH é gerada pelo Terraform (`tls_private_key`) e salva em `keys/`, que está no `.gitignore`.

**Estrutura**

```text
k8s-terraform-ansible/
├── terraform/
│   ├── versions.tf  provider.tf  variables.tf  terraform.tfvars  ha.tfvars
│   ├── vpc.tf  security-group.tf  ec2.tf
│   ├── main.tf        # NLB (HA), inventory automático, execução do Ansible
│   ├── outputs.tf
│   └── templates/inventory.tpl
├── ansible/
│   ├── ansible.cfg  site.yml  inventory.ini.example
│   ├── group_vars/all.yml
│   └── roles/ common · containerd · kubernetes · control-plane · worker · nginx-app
├── scripts/  validar-cluster.sh · baixar-kubeconfig.sh
├── docs/     arquitetura.md · evidencias/
├── keys/     (chave SSH gerada — fora do Git)
├── README.md
└── .gitignore
```

## 2. Pré-requisitos

Na sua máquina (Linux, macOS ou **WSL no Windows** — o Ansible não roda nativo no Windows):

| Ferramenta | Versão testada/mínima |
|---|---|
| Terraform | >= 1.5 |
| Ansible (`ansible-core`) | >= 2.15 |
| AWS CLI | v2 |
| ssh / curl | qualquer |

```bash
# Ubuntu / WSL
sudo apt update && sudo apt install -y python3-pip pipx curl unzip
pipx install ansible-core        # ou: pip install ansible-core
```

Versões usadas no cluster (ajustáveis em `ansible/group_vars/all.yml`): Kubernetes `v1.35`,
Calico `v3.32.2`, Ubuntu 24.04 LTS.

## 3. Configuração das credenciais AWS

As credenciais **nunca** ficam no código.

```bash
aws configure
# AWS Access Key ID: ...
# AWS Secret Access Key: ...
# Default region name: us-east-1

aws sts get-caller-identity      # confirma que as credenciais funcionam
```

Também funciona com `export AWS_PROFILE=meu-perfil` ou com as variáveis
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (AWS Academy: cole também `AWS_SESSION_TOKEN`).

## 4. Como executar o Terraform

```bash
cd terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Com `run_ansible = true` (padrão), **o `terraform apply` já roda o Ansible no final** e entrega o
cluster pronto com o NGINX (leva uns 10–15 minutos). Ao terminar, veja os outputs:

```bash
terraform output
```

Principais variáveis (`terraform/terraform.tfvars`):

| Variável | Padrão | Para que serve |
|---|---|---|
| `my_ip_cidr` | `""` | Seu IP /32. Vazio = detecta via checkip.amazonaws.com |
| `control_plane_count` | `1` | Acima de 1 ativa o modo HA com NLB |
| `worker_count` | `2` | Quantidade de workers |
| `enable_bastion` | `true` | Extra 3 |
| `run_ansible` | `true` | Extra 1 |
| `instance_type` | `t3.small` | 2 vCPU / 2 GB (mínimo do kubeadm) |

**Modo alta disponibilidade (Extra 4):**

```bash
terraform apply -var-file=terraform.tfvars -var-file=ha.tfvars
```

Cria 2 Control Planes + 3 Workers e um **Network Load Balancer interno** na porta 6443, usado
como `controlPlaneEndpoint` do kubeadm. O primeiro CP roda `kubeadm init --upload-certs`, o
Ansible gera a `--certificate-key` e o segundo CP entra com `kubeadm join --control-plane`.

> ⚠️ Com etcd empilhado, **2 Control Planes não toleram falha** (o quorum de 2 membros é 2).
> O desafio pede 2, mas para HA de verdade use `control_plane_count = 3`.

## 5. Como executar o Ansible

Se `run_ansible = true`, isso já aconteceu no passo anterior. Para rodar manualmente
(o playbook é idempotente, pode rodar quantas vezes quiser):

```bash
cd ansible
ansible all -i inventory.ini -m ping
ansible-playbook -i inventory.ini site.yml
```

O `inventory.ini` é **gerado pelo Terraform** (Extra 2). Com Bastion ativo, ele usa os IPs
privados e um `ProxyCommand` pelo Bastion. Veja o formato em `ansible/inventory.ini.example`.

O que cada role faz:

| Role | Tarefas |
|---|---|
| `common` | espera o cloud-init, `apt upgrade`, hostname, `/etc/hosts`, desliga swap, módulos `overlay`/`br_netfilter`, sysctl |
| `containerd` | instala, gera `config.toml`, `SystemdCgroup = true`, habilita e inicia o serviço |
| `kubernetes` | repositório `pkgs.k8s.io`, instala e trava (`hold`) kubeadm/kubelet/kubectl, habilita o kubelet |
| `control-plane` | `kubeadm init` (Pod CIDR `192.168.0.0/16`), Calico, join de CPs extras (HA), `~/.kube/config` |
| `worker` | pede o `kubeadm join` ao Control Plane (`delegate_to`) e executa em cada worker |
| `nginx-app` | espera todos os nós `Ready`, aplica Deployment (3 réplicas) + Service NodePort 30080, testa o HTTP |

Nenhum comando é copiado manualmente: o `kubeadm token create --print-join-command` roda no
Control Plane e o resultado é repassado pelo Ansible aos workers.

## 6. Como acessar o Kubernetes

**Pelo Control Plane** (o comando exato está no output `ssh_control_plane`):

```bash
$(terraform -chdir=terraform output -raw ssh_control_plane)
kubectl get nodes
```

Por baixo dos panos isso é: `ssh -i keys/k8s-lab-key.pem -J ubuntu@<bastion> ubuntu@<ip-privado-cp>`.

**Da sua máquina** (a porta 6443 está liberada só para o seu IP):

```bash
./scripts/baixar-kubeconfig.sh
export KUBECONFIG=$PWD/keys/kubeconfig
kubectl get nodes
```

## 7. Como validar o cluster

```bash
kubectl get nodes          # todos Ready
kubectl get pods -A        # calico-node, calico-kube-controllers, coredns, etcd... Running
kubectl get svc -A
```

Resultado esperado:

```text
NAME                STATUS   ROLES           AGE   VERSION
k8s-control-plane   Ready    control-plane   12m   v1.35.x
k8s-worker-1        Ready    <none>          10m   v1.35.x
k8s-worker-2        Ready    <none>          10m   v1.35.x
```

Ou rode tudo de uma vez e gere a evidência em `docs/evidencias/`:

```bash
./scripts/validar-cluster.sh
```

## 8. Como acessar a aplicação

```bash
kubectl get deployment     # nginx 3/3
kubectl get pods -o wide   # réplicas espalhadas entre os workers
kubectl get svc            # nginx NodePort 80:30080/TCP
terraform -chdir=terraform output nginx_urls
```

Abra no navegador `http://IP_PUBLICO_DO_WORKER:30080` — deve aparecer "Welcome to nginx!".
(A porta é liberada só para o seu IP; se o seu IP mudou, rode `terraform apply` de novo.)

## 9. Como destruir a infraestrutura

```bash
cd terraform
terraform destroy                                   # modo padrão
terraform destroy -var-file=terraform.tfvars -var-file=ha.tfvars   # se aplicou em modo HA
```

Depois confira no Console da AWS (EC2 → Instâncias, Load Balancers, Key Pairs; VPC) que não
sobrou nada com a tag `Project = k8s-lab`.

## 10. Problemas encontrados e como foram resolvidos

| Problema | Causa | Solução |
|---|---|---|
| `Could not get lock /var/lib/dpkg/lock-frontend` no primeiro `apt` | O cloud-init/unattended-upgrades ainda está rodando logo após o boot | `cloud-init status --wait` antes do apt e `lock_timeout: 300` |
| Pods do kube-system reiniciando em loop após o `kubeadm init` | containerd com cgroupfs e kubelet com systemd | `SystemdCgroup = true` no `config.toml` + `cgroupDriver: systemd` |
| Preflight: `/proc/sys/net/bridge/bridge-nf-call-iptables does not exist` | Módulo `br_netfilter` não carregado | `modprobe` + `/etc/modules-load.d/k8s.conf` + sysctl |
| Nós `NotReady` | Sem CNI instalada | Calico aplicado logo após o `kubeadm init` |
| Pods em nós diferentes não se comunicavam | Calico usa IP-in-IP (protocolo 4), que não é TCP/UDP | Regra "all traffic" usando o próprio SG como origem |
| Ansible não conectava nos nós após criar o Bastion | Nós sem SSH público | `ProxyCommand` pelo Bastion no inventory gerado |
| `kubeadm init` travava no modo HA | Hairpin do NLB: o CP chamava o NLB e caía nele mesmo com o IP de origem preservado | `preserve_client_ip = "false"` no target group + 6443 liberado para o CIDR da VPC |
| Timeout do `kubeadm init` no modo HA | Target novo do NLB demora a ficar healthy | `timeouts.controlPlaneComponentHealthCheck: 10m0s` |
| Hostname voltava ao nome da AWS após reboot | cloud-init redefine o hostname | `preserve_hostname: true` |
| NGINX inacessível depois de trocar de rede | SG liberado só para o IP antigo | `terraform apply` para atualizar `my_ip_cidr` |

> Atualize esta tabela com o que acontecer na execução do seu grupo.

---

## Testes obrigatórios (resumo)

```bash
# Terraform
terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan
terraform -chdir=terraform apply

# Ansible
cd ansible && ansible all -i inventory.ini -m ping && ansible-playbook -i inventory.ini site.yml && cd ..

# Kubernetes + aplicação
./scripts/validar-cluster.sh
```

## Regras atendidas

- Sem Amazon EKS; nada é instalado manualmente por SSH.
- Chave privada, state e inventory fora do Git (`.gitignore`); credenciais AWS só no `aws configure`.
- Ansible idempotente (verifica `kubelet.conf` antes de `init`/`join`, `creates:`, `changed_when`).
- `terraform destroy` remove tudo.
