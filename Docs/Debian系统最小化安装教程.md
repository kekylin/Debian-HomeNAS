# Debian系统最小化安装教程
系统安装视频演示流程：https://bilibili.com/video/BV1az42117pt/
## 1、Debian系统安装包下载
### 1.1 进入官网：https://www.debian.org ，点击其他下载链接
![image](https://github.com/user-attachments/assets/127b6543-c45e-42dc-a701-c1c88424427f)  
### 1.2 选择较庞大的完整安装映像，64 位 PC DVD-1 iso
![image](https://github.com/user-attachments/assets/d2f08c28-f606-4697-89f6-aa6f33a52172)  
因Debian系统在安装过程中需要联网更新安全源，国内访问速度有时候异常缓慢，动则几个小时。故国内用户建议按上面教程下载完整系统镜像包，这样将避免此问题发生，完成系统安装只需要四分钟左右，大大提高系统安装效率。
镜像写入工具推荐使用：https://etcher.balena.io/或https://rufus.ie/zh/  
## 2、选择安装方式（图形界面安装Graphical install）
![image](https://github.com/user-attachments/assets/4f1457db-b0e4-4e3b-a7cd-4e02513105e6)
## 3、设置系统默认语言（选英文，避免奇怪bug）
![image](https://github.com/user-attachments/assets/037e777a-212a-4a49-8535-3a890fc8c006)
## 4.1、设置系统时区（选other-Asia-China）
![image](https://github.com/user-attachments/assets/6aae51d0-05d7-474c-823a-16364534b08b)
## 4.2、选Asia
![image](https://github.com/user-attachments/assets/1e772eac-8c07-44f2-8c70-83245a435f6e)
## 4.3、选China
![image](https://github.com/user-attachments/assets/dbc09dbd-2858-40dd-a5ae-838384b1aba7)
## 5、设置区域语言（选United States en_US.UTF-8）
![image](https://github.com/user-attachments/assets/b12bef7a-d00e-4667-aa15-71f6c050e721)
## 6、设置键盘映射(选American English)
![image](https://github.com/user-attachments/assets/2d67d5c3-b57f-4d86-9af7-45a398c7d6ee)
## 7、设置主机名（一般保持默认，有冲突或不喜欢可更换）
![image](https://github.com/user-attachments/assets/7b98e356-55b1-48d6-93df-f7207fa9edd3)
## 8、设置域名（留空）
![image](https://github.com/user-attachments/assets/d86486f4-cb09-4184-a78c-35c7c3d9b28e)
## 9、设置管理员密码（root用户）
![image](https://github.com/user-attachments/assets/cec2eccf-fb50-42ce-9bbe-77b7110ba821)
## 10、创建新普通用户（用户全名）
![image](https://github.com/user-attachments/assets/41322ebd-49cd-47b1-9288-56a2b633f5bc)
## 11、新用户账户名称（登陆名称，建议和前面保持一致，避免出现混乱）
![image](https://github.com/user-attachments/assets/01322b41-00df-4057-9348-7c92a65e960b)
## 12、设置新用户密码（建议使用复杂密码）
![image](https://github.com/user-attachments/assets/cfeb3993-f878-4ab8-9bed-e5634da46df1)
## 13、进行系统盘磁盘分区（选Guided-use entire disk使用整个磁盘）
![image](https://github.com/user-attachments/assets/5b48a886-e63d-4a64-963c-7a8b276d4b56)
## 14、选择系统磁盘
![image](https://github.com/user-attachments/assets/88dde960-8bb9-455b-bf20-12bfce1a9a41)
## 15、选择分区方案（选All files in one partition将所有文件放在同一个分区）
![image](https://github.com/user-attachments/assets/4b5ad6e8-9a11-4a09-9d94-ca65980dce69)
## 16、完成分区操作并将修改写入磁盘（Finish partitioning and write changes to disk）
![image](https://github.com/user-attachments/assets/13c1bb93-2ef3-406f-9b36-004663bb3e2a)
## 17、再次确认写入磁盘（Yes）
![image](https://github.com/user-attachments/assets/6ec9fb8a-43f3-4f87-a977-d1af2f230951)
## 18、是否需要扫描额外安装介质（选No）
![image](https://github.com/user-attachments/assets/168ee1cc-806c-464d-918e-0d3dd8719a8a)
## 19、是否需要使用网络镜像站点（选No）
![image](https://github.com/user-attachments/assets/3c88f840-c36d-4182-bd1b-bc3912b5b61b)
## 20、是否要参加软件包流行度调查（选No）
![image](https://github.com/user-attachments/assets/018488c8-739d-4d27-bd84-350aa0f50bb8)
## 21、选择要安装的软件（建议只选最后两项）
![image](https://github.com/user-attachments/assets/6a4d320e-50b5-4e87-a1a5-549c4d5462a5)
## 22、系统正在安装中
![image](https://github.com/user-attachments/assets/f6b8ff02-d0c4-456f-af67-898b50f5eb3a)
## 23、系统已完成安装，点击Continue重启
![image](https://github.com/user-attachments/assets/cec61382-0550-44b3-8e08-72ba44951235)
## 24、安装完成后用root账户登陆系统，输入命令查询IP地址（路由器管理后台看也可）  
```shell
ip addr
```
![image](https://github.com/user-attachments/assets/cb0f8d92-7d07-408f-b2eb-0909a537bffa)
## 教程结束！
