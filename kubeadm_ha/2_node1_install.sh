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
