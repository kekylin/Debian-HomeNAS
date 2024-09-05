<h1 align="center">基于Debian搭建HomeNAS<br />
</h1>

一个将Debian系统快速配置成准NAS系统的脚本。可以轻松实现文件共享、照片备份、家庭影音、管理Docker、建立RAID等功能，使得Debian系统能够高效稳定地承担NAS任务。

## 主要特性
- 开源
- 安全
- 稳定
- 高效
- 自由

---
#### [搭建HomeNAS系列教程索引](https://docs.qq.com/doc/p/fa51c8a8545b12a5432df0efa9818d2939860ed0)
#### [脚本介绍](https://github.com/kekylin/Debian-HomeNAS/blob/main/Docs/%E8%84%9A%E6%9C%AC%E4%BB%8B%E7%BB%8D.md)
#### [成果展示](https://github.com/kekylin/Debian-HomeNAS/blob/main/Docs/%E6%88%90%E6%9E%9C%E5%B1%95%E7%A4%BA.md)
---

## 使用方法
### 1、安装系统
安装教程：[Debian系统最小化安装教程](https://github.com/kekylin/Debian-HomeNAS/blob/main/Docs/Debian%E7%B3%BB%E7%BB%9F%E6%9C%80%E5%B0%8F%E5%8C%96%E5%AE%89%E8%A3%85%E6%95%99%E7%A8%8B.md)
### 2、连接系统
系统安装完成后，使用SSH工具连接上系统。  
Debian默认禁止root账户直接通过SSH连接，所以用安装系统时创建的第一个普通用户账号进行登录。  
登陆后，必须使用以下命令切换到root账户。
  ```shell
su -
  ```

### 3、运行脚本
运行脚本前，建议先阅读脚本介绍，了解脚本能做什么先，脚本中的选项可以按需执行。运行脚本命令（二选一）  
**国内用户**
  ```shell
bash <(wget -qO- https://gitee.com/kekylin/Debian-HomeNAS/raw/main/debian-homenas_cn.sh)
  ```
**Github直连**
  ```shell
bash <(wget -qO- https://raw.githubusercontent.com/kekylin/debian-homenas/main/debian-homenas.sh)
  ```

### 4、登陆使用
> **脚本执行完毕后，查看SSH工具显示的Cockpit面板管理地址和Docker管理工具地址，打开对应服务进行使用。**

Cockpit  
一个基于 Web 的服务器图形界面，在 Web 浏览器中查看您的服务器并使用鼠标执行系统任务。启动容器、管理存储、配置网络和检查日志都很容易。基本上，您可以将 Cockpit 视为图形“桌面界面”。
Cockpit是直接使用系统账户进行登陆使用，出于安全考虑，Cockpit默认禁用root账户登陆，建议使用您安装系统时创建的第一个用户登陆。
  ```shell
https://localhost:9090
  ```
Portainer  
一个Docker的可视化工具，可提供一个交互界面显示Docker的详细信息供用户操作。功能包括状态显示、应用模板快速部署、容器镜像网络数据卷的基本操作（包括上传下载镜像，创建容器等操作）、事件日志显示、容器控制台操作、Swarm集群和服务等集中管理和操作、登录用户管理和控制等功能。
  ```shell
https://localhost:9443
  ```

## 转载请保留出处
- Debian-HomeNAS交流群：339169752
