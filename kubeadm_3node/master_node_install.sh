#! /bin/bash

# 可以在 kubeadm init 之前运行 kubeadm config images pull，以验证与 gcr.io 容器镜像仓库的连通性
# https://kubernetes.io/zh/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#%E5%88%9D%E5%A7%8B%E5%8C%96%E6%8E%A7%E5%88%B6%E5%B9%B3%E9%9D%A2%E8%8A%82%E7%82%B9
kubeadm init \
--apiserver-advertise-address=192.168.10.21 \
--image-repository registry.aliyuncs.com/google_containers \
--kubernetes-version v1.18.0 \
--service-cidr=10.96.0.0/12 \
--pod-network-cidr=10.244.0.0/16