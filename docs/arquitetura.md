# Diagrama da arquitetura

## Infraestrutura AWS (modo padrão: 1 Control Plane + 2 Workers + Bastion)

```mermaid
flowchart TB
    user(["👤 Aluno<br/>(seu IP /32)"])

    subgraph AWS["☁️ AWS — us-east-1"]
        subgraph VPC["VPC 10.0.0.0/16"]
            igw["Internet Gateway"]

            subgraph SB["Subnet Bastion 10.0.3.0/24"]
                bastion["🛡️ EC2 k8s-bastion<br/>SSH liberado só para o seu IP"]
            end

            subgraph SCP["Subnet Control Plane 10.0.1.0/24"]
                cp["EC2 k8s-control-plane<br/>kube-apiserver · etcd<br/>scheduler · controller-manager"]
            end

            subgraph SW["Subnet Workers 10.0.2.0/24"]
                w1["EC2 k8s-worker-1"]
                w2["EC2 k8s-worker-2"]
            end
        end
    end

    user -- "SSH 22" --> bastion
    bastion -- "SSH 22 (ProxyCommand)" --> cp
    bastion -- "SSH 22" --> w1
    bastion -- "SSH 22" --> w2
    user -- "HTTP 30080 (NodePort)" --> w1
    user -- "HTTP 30080 (NodePort)" --> w2
    user -. "kubectl 6443" .-> cp
    cp <-- "Calico IP-in-IP · kubelet 10250 · API 6443" --> w1
    cp <-- "Calico IP-in-IP · kubelet 10250 · API 6443" --> w2
```

## Camadas do cluster

```mermaid
flowchart TB
    AWS --> VPC
    VPC --> CP["Control Plane"]
    VPC --> WK["Workers"]
    CP --> K8S["Kubernetes (kubeadm · kubelet · containerd)"]
    WK --> K8S
    K8S --> CALICO["Calico (CNI) — Pod CIDR 192.168.0.0/16"]
    CALICO --> NGINX["Deployment nginx (3 réplicas)<br/>Service NodePort 30080"]
```

## Fluxo de provisionamento (Extras 1 e 2)

```mermaid
flowchart LR
    A["terraform apply"] --> B["VPC · Subnets · IGW · Route Table"]
    B --> C["Security Groups"]
    C --> D["EC2: Bastion · Control Plane · Workers"]
    D --> E["templatefile() → ansible/inventory.ini"]
    E --> F["terraform_data + local-exec<br/>ansible-playbook site.yml"]
    F --> G["common → containerd → kubernetes"]
    G --> H["kubeadm init + Calico"]
    H --> I["kubeadm join (workers)"]
    I --> J["NGINX + teste do NodePort"]
```

## Modo HA (Extra 4: 2 Control Planes + 3 Workers)

```mermaid
flowchart TB
    subgraph VPC["VPC 10.0.0.0/16"]
        nlb["NLB interno TCP 6443<br/>(controlPlaneEndpoint)"]
        cp1["k8s-control-plane-1<br/>apiserver + etcd"]
        cp2["k8s-control-plane-2<br/>apiserver + etcd"]
        w1["k8s-worker-1"]
        w2["k8s-worker-2"]
        w3["k8s-worker-3"]
    end

    nlb --> cp1
    nlb --> cp2
    cp1 <-. "replicação etcd" .-> cp2
    w1 --> nlb
    w2 --> nlb
    w3 --> nlb
```

Todos os kubelets e o `kubectl` dos Control Planes falam com a API pelo DNS do NLB, então
qualquer API Server pode atender. O etcd fica "empilhado" (stacked) em cada Control Plane.
