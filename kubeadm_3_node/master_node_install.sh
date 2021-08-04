#! /bin/bash

kubeadm init \
--apiserver-advertise-address=192.168.1.21 \
--image-repository registry.aliyuncs.com/google_containers \
--kubernetes-version v1.18.0 \
--service-cidr=10.96.0.0/12 \
--pod-network-cidr=10.244.0.0/16