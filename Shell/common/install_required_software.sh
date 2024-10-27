#!/bin/bash

# 更新软件源
sudo apt update

# 安装必备软件
sudo apt install -y sudo curl git vim wget exim4 gnupg apt-transport-https ca-certificates smartmontools
