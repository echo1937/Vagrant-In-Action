#! /bin/bash

# 添加解析
cat >> /etc/hosts << EOF
192.168.10.20 master
192.168.10.128 node1
192.168.10.129 node2
192.168.10.130 node3
192.168.10.131 node4
EOF

# 将桥接的IPv4流量传递到iptables的链
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# 安装工具软件
yum install -y wget vim

# 安装docker
wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -O /etc/yum.repos.d/docker-ce.repo
yum install -y docker-ce-18.06.1.ce-3.el7

# 添加镜像加速 https://cr.console.aliyun.com/cn-hangzhou/instances/mirrors
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://h35bbdsw.mirror.aliyuncs.com"]
}
EOF

# 配置docker代理 https://docs.docker.com/config/daemon/systemd/
sudo mkdir -p /etc/systemd/system/docker.service.d
cat <<EOF >/etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=http://192.168.10.1:10800"
Environment="NO_PROXY=localhost,127.0.0.1,docker-registry.example.com,.corp"
EOF
systemctl enable docker
systemctl start docker


# 添加Kubernetes镜像 https://developer.aliyun.com/mirror/kubernetes
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

# 安装kubeadm, kubelet和kubectl
yum install -y kubelet-1.18.0 kubeadm-1.18.0 kubectl-1.18.0
systemctl enable kubelet && systemctl start kubelet

# 如果没有设置docker的代理, 需要下载flanneld从本地导入
# docker load < /vagrant/flanneld-v0.14.0-amd64.docker