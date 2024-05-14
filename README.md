<h1 align="center">基于Debian搭建HomeNAS<br />
</h1>
  
这是根据《基于Debian搭建HomeNAS》教程所写的半自动化配置脚本。
# [搭建HomeNAS系列教程索引](https://docs.qq.com/doc/p/fa51c8a8545b12a5432df0efa9818d2939860ed0)
---
#### 成果展示
![最终成果展示](https://github.com/kekylin/Debian-HomeNAS/assets/65521882/680df62e-7f6a-4b10-89a5-56cb363eecc8)
#### 服务器状态监测
![服务器状态监测](https://github.com/kekylin/Debian-HomeNAS/assets/65521882/dbbcf50a-fb51-4672-9e46-16e03fb0a1d2)
#### 外网访问来源
![服务访问监测](https://github.com/kekylin/Debian-HomeNAS/assets/65521882/9491d322-4859-4e8c-8e59-14964e82f388)
#### Cockpit管理面板
![cockpit](https://github.com/kekylin/Debian-HomeNAS/assets/65521882/7716ac69-ae19-426e-9cf6-b04e141747c4)
#### Docker服务管理
![dockge](https://github.com/kekylin/Debian-HomeNAS/assets/65521882/6ac949d3-f39c-4e37-b8bf-2f42557f909d)
#### Jellyfin影音服务
![image](https://github.com/kekylin/Debian-HomeNAS/assets/65521882/c888cde7-30d5-4dc9-9fc1-5f898c8bca32)

# 脚本已实现功能
### 一、系统安装  
1.1 系统镜像下载  
1.2 安装教程  
### 二、系统初始化  
2.1 安装初始必备软件 （已实现）  
2.2 添加用户至sudo组 （已实现）  
2.3 更换国内镜像源 （已实现）  
2.4 更新系统 （已实现）  
### 三、安装Cockpit Web管理面板  
3.1 安装Cockpit （已实现）  
3.2 安装Cockpit附属组件 （已实现）  
3.3 Cockpit调优  
### 四、系统调优  
4.1 设置Cockpit接管网络配置 （已实现）  
4.2 调整系统时区/时间  
4.3 交换空间优化  
4.4 安装Tuned系统调优工具 （已实现）  
4.5 新用户默认加入user组  
4.6 修改homes目录默认路径  
4.7 修改用户home目录默认权限  
4.8 创建新用户  
4.9 创建容器专属账户  
4.10 配置邮件发送服务 （已实现）  
4.11 添加Github Hosts  
4.12 添加TMDB Hosts  
4.13 WireGuard家庭组网  
### 五、安全防护  
5.1 配置高强度密码策略  
5.2 用户连续登陆失败锁定  
5.3 禁止root用户密码登陆  
5.4 限制指定用户外网登陆  
5.5 限制指定用户夜间登陆  
5.7 限制用户同时登陆数量  
5.6 限制用户SU （已实现）  
5.8 用户登陆邮件通知告警 （已实现）  
5.9 超时自动注销活动状态 （已实现）  
5.10 记录所有用户的登录和操作日志 （已实现）  
5.11 禁止SSH服务开机自启动  
5.11 安装防火墙  
5.12 安装自动封锁软件  （已实现）  
5.14 安装病毒防护软件  
### 六、存储管理  
6.1 硬盘管理  
6.2 软Raid管理  
6.3 硬盘自动休眠  
6.4 硬盘健康监测  
6.5 安装联合文件系统  
6.5 安装SnapRaid  
### 七、Docker服务  
7.1 Docker安装 （已实现）  
7.2 容器管理 （已实现）  
7.2 反向代理  
7.3 数据库  
7.4 文件存储  
7.5 影音服务  
7.6 下载服务  
7.7 照片管理  
7.8 Blog管理  
7.9 薅羊毛  
### 八、UPS不断电系统  
---

# 使用方法
### 1、使用SSH连接系统，登陆账户是安装系统时创建的第一个用户，然后用下面命令切换root账户。Debian系统默认禁用root账户通过SSH连接系统。
  ```shell
su -
  ```
### 2、执行脚本下载命令并自动运行
  ```shell
wget -O debian-homenas.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/debian-homenas/main/debian-homenas.sh && bash debian-homenas.sh
  ```
### 2、登陆使用
> **脚本执行完毕后，查看SSH工具显示的Cockpit面板管理地址和Docker管理工具地址，打开对应服务进行使用。**

Cockpit，一个基于 Web 的服务器图形界面，在 Web 浏览器中查看您的服务器并使用鼠标执行系统任务。启动容器、管理存储、配置网络和检查日志都很容易。基本上，您可以将 Cockpit 视为图形“桌面界面”。
Cockpit是直接使用系统账户进行登陆使用，出于安全考虑，Cockpit默认禁用root账户登陆，建议使用您安装系统时创建的第一个用户登陆。
  ```shell
https://localhost:9090
  ```
Portainer，通用容器管理平台，脚本部署的是英文原版，与Dockge配合使用，涉及到网络管理、容器镜像管理，使用Portainer。日常部署容器及维护容器，推荐使用Dockge，支持中文，对容器的管理和维护很方便。
  ```shell
https://localhost:9443
  ```
Dockge,一个精美的、易于使用的、反应式的自托管 docker compose.yaml 面向堆栈的管理器。自带中文，日常维护时，不管是部署、更新还是维护，都比Portainer方便，但目前缺少容器网络管理及容器镜像功能，推荐搭配Portainer使用。
  ```shell
http://localhost:5001
  ```

# 转载请保留出处
- DIY NAS_3群 339169752
