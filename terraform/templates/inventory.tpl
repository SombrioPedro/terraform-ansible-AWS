# ARQUIVO GERADO PELO TERRAFORM (Extra 2) — não edite manualmente.

[control_plane]
%{ for n in control_planes ~}
${n.name} ansible_host=${use_bastion ? n.private_ip : n.public_ip} private_ip=${n.private_ip} public_ip=${n.public_ip}
%{ endfor ~}

[workers]
%{ for n in workers ~}
${n.name} ansible_host=${use_bastion ? n.private_ip : n.public_ip} private_ip=${n.private_ip} public_ip=${n.public_ip}
%{ endfor ~}

[k8s_cluster:children]
control_plane
workers

[k8s_cluster:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=${key_path}
control_plane_endpoint=${api_endpoint}
%{ if use_bastion ~}
bastion_ip=${bastion_ip}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -W %h:%p -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${key_path} ubuntu@${bastion_ip}"'
%{ else ~}
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
%{ endif ~}
