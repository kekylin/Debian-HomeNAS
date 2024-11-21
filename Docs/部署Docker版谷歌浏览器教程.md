# 1、阅读项目文档

## 谷歌浏览器
https://github.com/linuxserver/docker-chromium

## Edge浏览器
https://github.com/linuxserver/docker-msedge

## 火狐浏览器
https://github.com/linuxserver/docker-firefox

# 2、配置国内镜像源（解决中文字体安装问题）
新建文件sources.list，内容填写国内镜像源地址，保存。  
```shell
deb https://mirrors.bfsu.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.bfsu.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.bfsu.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb https://mirrors.bfsu.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
```

# 3、部署参数

## docker cli
```shell
docker run -d \
  --name=chromium \
  --hostname=chromium \
  --security-opt=no-new-privileges:true \
  --security-opt seccomp=unconfined \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e CUSTOM_USER=admin \
  -e PASSWORD=admin \
  -e DOCKER_MODS=linuxserver/mods:universal-package-install \
  -e INSTALL_PACKAGES=fonts-noto-cjk \
  -e LC_ALL=zh_CN.UTF-8 \
  -e TITLE=Chromium \
  -p 3000:3000 \
  -p 3001:3001 \
  -v /opt/docker/chromium:/config \
  -v /opt/docker/chromium/sources.list:/etc/apt/sources.list \
  --shm-size="2gb" \
  --restart unless-stopped \
  linuxserver/chromium:latest
```

## docker-compose
```shell
services:
  chromium:
    image: linuxserver/chromium:latest
    container_name: chromium
    hostname: chromium
    security_opt:
      - no-new-privileges:true
      - seccomp=unconfined
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - CUSTOM_USER=admin
      - PASSWORD=admin
      - DOCKER_MODS=linuxserver/mods:universal-package-install
      - INSTALL_PACKAGES=fonts-noto-cjk
      - LC_ALL=zh_CN.UTF-8
      - TITLE=Chromium
    volumes:
      - /opt/docker/chromium:/config
      - /opt/docker/chromium/sources.list:/etc/apt/sources.list
    ports:
      - 3000:3000
      - 3001:3001
    shm_size: 2gb
    restart: unless-stopped
```

# 4、运行容器
```shell
docker compose up -d
```

# 5、Edge浏览器、火狐浏览器部署思路与此相同。


