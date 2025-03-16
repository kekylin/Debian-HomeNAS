# Cockpit启用SMB文件共享
## 一、安装必备Cockpit附属组件
### 1.1 配置45Drives Repo安装脚本
【注意：如果是通过本项目脚本安装的Cockpit，默认已安装好Navigator、File Sharing、Identities组件，请跳过此步骤。】  

安装脚本将自动检测您的发行版并将适当的文件添加到您的系统。该脚本还将保存任何与 45Drives 相关的旧存储库（如果存在）。
下面的命令将下载并运行脚本，而不会在您的系统上留下任何东西！
```shell
curl -sSL https://repo.45drives.com/setup | sudo bash
sudo apt update
```
（来源：https://repo.45drives.com/setup.html）

Navigator、File Sharing、Identities安装命令：
```shell
sudo apt install cockpit-navigator cockpit-file-sharing cockpit-identities -y
```
上述命令执行后将安装Navigator文件浏览器，Cockpit的特色文件浏览器；File Sharing插件，可轻松管理 Samba 和 NFS 文件共享；Cockpit Identities，用户和组管理插件。
安装完成后打开Cockpit Web管理面板，可以在左侧工具栏看到。
![image](https://github.com/user-attachments/assets/11b4bc73-db5b-483b-a293-b874bf73ab58)

## 二、启用SMB文件共享
SMB全局设置：设置日志等级、优化MacOS的使用
![image](https://github.com/user-attachments/assets/f14eda3d-349f-4772-9fa3-b6ae04557d34)

添加需要共享的文件夹，点击Shares右侧的“+”号
![image](https://github.com/user-attachments/assets/f5e08db7-f098-4280-b684-abcf2f53fb15)

按下图说明添加需要共享出去的文件夹，设置好共享文件夹信息后，点击Confirm保存设置。
![image](https://github.com/user-attachments/assets/b5ef94ee-32e9-4e44-b6bb-fc0d29ca6e84)

如需填写更多自定义SMB参数，可通过Advanced选项输入。  

SMB 共享配置文件参数的一些基本解释：
```shell
Guest OK: 这个设置允许或不允许未经身份验证的用户（即"访客"）访问该共享。如果设置为"是"，那么任何人，即使没有有效的用户凭证，也可以访问该共享。
Read Only: 如果这个设置被启用，那么用户只能读取共享中的文件，而不能修改它们。
Browseable: 如果设置为"是"，该共享将在网络中可见，用户可以在浏览网络共享时看到它。
Windows ACLs: "ACL" 是 "Access Control List" 的缩写，它是一个权限列表，用于确定特定用户或用户组对特定文件或目录的访问权限。"Windows ACLs" 允许你从 Windows 系统管理这些权限。
Windows ACLs with Linux/MacOS Support: 这个选项类似于 "Windows ACLs"，但是它还允许你管理针对 Windows、Mac 和 Linux 客户端的权限。
Shadow Copy: "Shadow Copy" 是一种在 Windows 系统中创建文件或文件夹备份的技术。启用这个选项会向用户公开每个文件的快照。
MacOS Share: 这个选项优化了共享服务，使其更好地服务于 MacOS 用户。
Audit Logs: 启用此选项将开启审计日志，记录所有访问该共享的活动，包括谁访问了它，什么时间访问，以及他们做了什么。
Advanced Settings: 这通常是一个可以展开的部分，其中包含更多的详细设置选项，允许你更深入地自定义你的共享配置。
```
添加完成后可以在Shares栏看到已经共享的文件夹。右侧有两个按钮，一个是修改共享设置信息，一个是删除共享文件夹（只删除共享状态，不会删除共享文件夹中的文件。）
![image](https://github.com/user-attachments/assets/9d5013db-2fc9-4d4a-994a-7359448ae0f4)

## 三、设置SMB用户的账户密码
打开File Sharing插件，点击Users
![image](https://github.com/user-attachments/assets/3a3f49dd-34ce-4298-8855-e0f0590a80c2)

点需要设置的用户，这里以test用户为例
![image](https://github.com/user-attachments/assets/6f814eb2-ff1b-43ec-929f-72e5a2afec35)

设置用户的SMB访问密码，此密码只能用来访问SMB共享文件夹，不是系统的登陆密码，不能用于登陆系统，和系统登陆密码是完全分开的。
![image](https://github.com/user-attachments/assets/3d68ff10-50bb-4279-8a42-a544d98b345d)

设置密码
![image](https://github.com/user-attachments/assets/f3431c5f-b5a9-42d6-b7ef-8503ab9c607c)

修改用户SMB登陆密码或删除密码（后续维护）
![image](https://github.com/user-attachments/assets/ebaa14d5-e55f-4997-9c01-618337caf6c4)

## 四、通过Windows系统访问SMB共享文件夹
输入地址访问，推荐通过主机IP地址进行访问，格式为`\\192.168.1.10`，IP地址改为您服务器实际地址。  

![image](https://github.com/user-attachments/assets/8c530786-11c2-4df6-9684-b0fb59970883)

访问成功（注意，如果访问被拒绝，请检查当前登陆用户是否有权限访问上面设置的共享目录。）
![image](https://github.com/user-attachments/assets/ff7acb0f-35c8-4eff-b140-7c12699bd055)
