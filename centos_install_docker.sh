#!/bin/bash

#更新内核
# 安装docker环境依赖

yum install -y yum-utils device-mapper-persistent-data lvm2
# 配置国内docker的yum源（阿里云）

yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
# 安装docker-ce

yum install docker-ce docker-ce-cli containerd.io -y
# yum info 启动和设置开机启动

systemctl start docker && systemctl enable docker

#增加镜像加速器地址vi /etc/docker/daemon.json 写入下面内容保存，阿里云地址每人都不一样登录阿里云，容器镜像服务查找
cat << "EOF" > /etc/docker/daemon.json

{
"registry-mirrors": ["https://docker.mirrors.ustc.edu.cn","https://dockerhub.azk8s.cn"]
}

EOF

#重启docker

systemctl restart docker 

#安装docker portainer 控制面板完成后http://IP:9000

#英文


# docker run -d -p 9000:9000 --name portainer --restart always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer
#中文


docker run -d --restart=always --name="portainer" -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data 6053537/portainer-ce
# 控制面板完成后http://IP:9000



rm -rf centos_install_docker.sh
# 重启



