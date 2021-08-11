本文是kubeadm高可用环境的搭建教程, 使用--upload-certs简化了证书分发, 并尽可能用命令行来代替yaml部署.

## 1. 安装要求

在开始之前，部署Kubernetes集群机器需要满足以下几个条件：

- 一台或多台机器，操作系统 CentOS7.x-86_x64
- 硬件配置：2GB或更多RAM，2个CPU或更多CPU，硬盘30GB或更多
- 可以访问外网，需要拉取镜像，如果服务器不能上网，需要提前下载镜像并导入节点
- 禁止swap分区

## 2. 准备环境

| 角色           | IP             |
| ------------- | -------------- |
| master(虚拟)   | 192.168.10.20  |
| node1         | 192.168.10.21  |
| node2         | 192.168.10.22  |
| node3         | 192.168.10.23  |
| node4         | 192.168.10.24  |

执行脚本: 1_all_node_install.sh

执行对象: node1、2、3、4

```shell script
#! /bin/bash

# 添加解析
cat >> /etc/hosts << EOF
192.168.10.20 master
192.168.10.21 node1
192.168.10.22 node2
192.168.10.23 node3
192.168.10.24 node4
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
```


## 2. node1、2、3的keepalived和haproxy 

执行脚本: 2_node{1,2,3}_install.sh

执行对象: node1/node2/node3

```shell script
#!/bin/bash

yum install -y conntrack-tools libseccomp libtool-ltdl
yum install -y keepalived

cat > /etc/keepalived/keepalived.conf <<EOF
! Configuration File for keepalived

global_defs {
   router_id k8s
}

vrrp_script check_haproxy {                # haproxy服务启动
    script "killall -0 haproxy"            # 检查haproxy进程是否存在
    interval 3
    weight -2
    fall 10
    rise 2
}

vrrp_instance VI_1 {
    state MASTER                           # 主机为MASTER, 备机为BACKUP
    interface eth0                         # 监测网络端口, 用ipconfig查看
    virtual_router_id 51                   # 主备机必须相同
    priority 250                           # 主备机取不同的优先级, 要主大备小, 从服务器上改为120
    advert_int 1                           # VRRP Multicast广播周期秒数

    authentication {
        auth_type PASS                     # VRRP认证方式
        auth_pass ceb1b3ec013d66163d6ab    # VRRP口令, 主备机密码必须相同
    }

    virtual_ipaddress {
        192.168.10.20                       # VIP漂移地址, 即集群IP地址
    }

    track_script {                         # 调用haproxy进程检测脚本
        check_haproxy
    }

}
EOF

systemctl enable keepalived.service
systemctl start keepalived.service


yum install -y haproxy
cat > /etc/haproxy/haproxy.cfg << EOF
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    # to have these messages end up in /var/log/haproxy.log you will
    # need to:
    # 1) configure syslog to accept network log events.  This is done
    #    by adding the '-r' option to the SYSLOGD_OPTIONS in
    #    /etc/sysconfig/syslog
    # 2) configure local2 events to go to the /var/log/haproxy.log
    #   file. A line like the following can be added to
    #   /etc/sysconfig/syslog
    #
    #    local2.*                       /var/log/haproxy.log
    #
    log         127.0.0.1 local2                  # 日志输出配置，所有日志都记录在本机，通过local2输出

    chroot      /var/lib/haproxy                  # Haproxy安装目录
    pidfile     /var/run/haproxy.pid              # 将所有进程写入pid文件
    maxconn     4000                              # 限制单个进程的最大连接数
    user        haproxy                           # 所属运行用户，默认99为nobody
    group       haproxy                           # 所属运行用户组，默认99为nobody
    daemon                                        # 让进程作为守护进程在后台运行

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats
#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http                  # 所处理的类别,默认采用http模式，可配置成tcp作4层消息转发
    log                     global
    option                  httplog               # http 日志格式
    option                  dontlognull           # 不记录空连接
    option http-server-close                      #
    option forwardfor       except 127.0.0.0/8    # 如果后端服务器需要获得客户端真实ip需要配置的参数，可以从Http Header中获得客户端ip
    option                  redispatch            # 在连接失败或断开的情况下，允许当前会话被重新分发
    retries                 3                     # 设置在一个服务器上链接失败后的重连次数
    timeout http-request    10s                   #
    timeout queue           1m
    timeout connect         10s                   # 设置等待连接到服务器成功的最大时间
    timeout client          1m                    # 设置客户端的最大超时时间
    timeout server          1m                    # 设置服务器端的最大超时时间
    timeout http-keep-alive 10s
    timeout check           10s                   # 心跳检测时间
    maxconn                 3000                  # 限制单个进程的最大连接数
#---------------------------------------------------------------------
# kubernetes apiserver frontend which proxys to the backends
#---------------------------------------------------------------------
frontend kubernetes-apiserver
    mode                 tcp
    bind                 *:16443
    option               tcplog
    default_backend      kubernetes-apiserver
#---------------------------------------------------------------------
# round robin balancing between the various backends
#---------------------------------------------------------------------
backend kubernetes-apiserver
    mode        tcp
    balance     roundrobin
    server      node1   192.168.10.21:6443 check
    server      node2   192.168.10.22:6443 check
    server      node3   192.168.10.23:6443 check
#---------------------------------------------------------------------
# collection haproxy statistics message
#---------------------------------------------------------------------
listen stats
    bind                 *:1080
    stats auth           admin:admin
    stats refresh        5s
    stats realm          HAProxy\ Statistics
    stats uri            /admin?stats
EOF


systemctl enable haproxy
systemctl start haproxy
```

keepalived: node1、node2、node3的master节点会获得VIP 192.168.10.20;

haproxy: 监听在*:16443端口, 192.168.10.20:16443(作为--control-plane-endpoint)是load balancer的端点, 收到的请求会rr到node1、2、3(API Server)的:6443端口;


## 3. 控制平面的kubeadm init过程

执行脚本: 3_master_node_install.sh

执行对象: node1

```shell script
kubeadm init \
--control-plane-endpoint "master:16443" --upload-certs \
--image-repository registry.aliyuncs.com/google_containers \
--kubernetes-version v1.18.0 \
--service-cidr=10.96.0.0/12 \
--pod-network-cidr=10.244.0.0/16
``` 

--control-plane-endpoint: 控制平面的LB地址

--pod-network-cidr: 配合flanneld进行pod网络的划分

## 4. 安装网络CNI插件

```shell script
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

## 5. 其他控制节点的加入

```shell script
  kubeadm join master:16443 --token vvj6vk.vhz1qb4tgwsjwyne \
    --discovery-token-ca-cert-hash sha256:bd4727642e7ab62eb4b206cea1f4611748a3c1922d6eded3f21a52eaddb4007c \
    --control-plane --certificate-key 7cd0ee0b3f1b6ea6f11044b22c6adcd28edff466b376d68be825ced269685885
```

## 6. 其他工作节点的加入

```shell
kubeadm join master:16443 --token vvj6vk.vhz1qb4tgwsjwyne \
    --discovery-token-ca-cert-hash sha256:bd4727642e7ab62eb4b206cea1f4611748a3c1922d6eded3f21a52eaddb4007c
```

## 7. 注意

1. 本高可用方案中, 建议只保留的eth0以简化网络结构, 否则设置不当容易发生 [node "node1" not found错误](https://www.cnblogs.com/taoweizhong/p/11545953.html) 和etcd health check的错误;
2. 在公有云环境中, 推荐使用类似AWS EKS的服务; 在实验环境中, 更推荐使用单独的节点假设keepalived/haproxy服务, 便于排查和调试;
3. 其他控制节点的加入必须在安装CNI插件之后, 否则是无法加入到现有环境的;

