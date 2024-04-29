# 基于Debian搭建HomeNAS
这是《基于Debian搭建HomeNAS》教程所写的半自动化配置脚本，目前脚本已经实现教程中以下章节操作。

# 已实现功能
### 二、系统初始化
- 2.1 安装初始必备软件
- 2.2 添加用户至sudo组
- 2.3 更换国内镜像源
- 2.4 更新系统
### 三、安装Cockpit Web管理面板
- 3.1 安装Cockpit
- 3.2 安装Cockpit附属组件
官方组件
- 1、虚拟机
- 2、Podman 容器
第三方组件
- 1、Navigator文件浏览器，Cockpit 的特色文件浏览器。
- 2、File Sharing，一个 Cockpit 插件，可轻松管理 Samba 和 NFS 文件共享。
- 3、Cockpit Identities，用户和组管理插件。
- 自动注销闲置的用户
- 在登录页面中添加标题
- Cockpit面板登陆后首页展示信息
### 四、系统调优
- 4.1 设置Cockpit接管网络配置
- 4.4 安装Tuned系统调优工具
### 五、安全防护
- 5.8 用户登陆邮件通知告警
- 5.9 超时自动注销活动状态
- 5.10 记录所有用户的登录和操作日志
### 七、Docker服务
- 7.1 Docker安装
- 7.2 容器管理

# 使用方法
### 1、使用SSH连接系统，切换root账户
  ```shell
su -
  ```
### 2、执行脚本下载命令并自动运行
  ```shell
wget -O debian-homenas.sh -q --show-progress https://mirror.ghproxy.com/https://raw.githubusercontent.com/kekylin/debian-homenas/main/debian-homenas.sh && bash debian-homenas.sh
  ```
# 转载请保留出处
- DIY NAS_3群 339169752
