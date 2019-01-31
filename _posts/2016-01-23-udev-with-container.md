---
layout: post
title: "特权容器对宿主机udev影响"
author: Ahao Mu
excerpt: 特权容器对宿主机udev影响
tags:
- Linux
- Container
---

## 背景
通过--privileged 启动的特权容器拥有了真正的root权限，这类特权容器可能会对物理机有什么潜在的影响呢？本文讲的就是一个最近遇到的问题; 

广告业务的容器在特权模式下，挂载了物理上的/dev/tlock 设备，这个设备在物理机上被设置了权限chmod 666 /dev/tlock

多个容器共享物理机上的/dev/tlock设备，当重启其中一个容器，发现物理机上/dev/tlock设备权限被更改,从而影响了业务。这里重要的问题的就是重启容器不应该影响到物理机

那么我们的疑问是--priviledged权限下的容器，如何和宿主机下的/dev/xxx 产生冲突的？ 如何对宿主机产生影响的

## 复现
这个问题很容易复现，通过启动特权容器，编写udev rules规则就可以把表面行为分析清楚

#### 场景1: 使用--privileged
容器中添加：

```
#cat  /etc/udev/rules.d/70-muahao.rules
KERNEL=="random",  GROUP="root", MODE="0660", OPTIONS="last_rule"
```
物理机中添加：

```
#cat  /etc/udev/rules.d/70-muahao.rules
KERNEL=="random",  GROUP="root", MODE="0660", OPTIONS="last_rule"
```
宿主机：

```
#chmod 777 /dev/random
```

重启容器

宿主机的/dev/random权限变成0660：

```
#ll /dev/random
crw-rw---- 1 root root 1, 8 Aug  8 10:45 /dev/random
```

容器的/dev/random权限变成0660:

```
#ll /dev/random
crw-rw---- 1 root root 1, 8 Aug  8 10:45 /dev/random
```

结论： 使用--priviledged 的容器重启后，如果容器和宿主机分别都配置了udev rules 规则，容器和宿主机分别根据自己的udev rules 规则，修改/dev/xxx 权限



#### 场景2:不使用--privileged
在容器中执行，期望改成0777

```
#cat  /etc/udev/rules.d/70-muahao.rules
KERNEL=="random",  GROUP="root", MODE="0777", OPTIONS="last_rule"
```

重启容器后

在容器中查看/dev/random权限：还是0666，而非0777

```
#ll /dev/random
crw-rw-rw- 1 root root 1, 8 Aug  8 11:08 /dev/random
```

在物理机上：
没有收到影响

结论： 
不使用--prividgesd启动的容器情况下，如果，我们分别给容器，宿主机配置udev rules，那么重启容器后,  容器和宿主机都不会读取udev rules 

## /dev && udev rules
/dev 是一个is not a "real" filesystem, it is a devtmpfs，比如可能是tmpfs 或者ramdisk,其唯一目的是保持在引导时由udev创建的设备节点。

你可以看到：

```
# df -T /dev
Filesystem     Type     1K-blocks  Used Available Use% Mounted on
udev           devtmpfs    498256     0    498256   0% /dev
```

Because it is a ramdisk, the contents do not survive a reboot. This is intentional, and not a problem - udev will create the device nodes needed by the system at boot time.

简而言之，/dev/是一个内存中虚拟文件系统存在，udev会在启动过程中，管理创建/dev/xxx设备文件，包括权限。而非systemd操作；启动过程中包含了udev程序这一环节

比如：/dev/random 默认权限是0666 ，如果你想把它设置成0777，有两种方法：

1. 添加rules规则： /etc/udev/rules.d/ 
2. 利用rc.local

```
#echo "chmod 777 /dev/random" >> /etc/rc.d/rc.local
#chmod u+x /etc/rc.d/rc.local
#reboot
```

## udevadm找到问题突破点
[https://stackoverflow.com/questions/36880565/why-dont-my-udev-rules-work-inside-of-a-running-docker-container](https://stackoverflow.com/questions/36880565/why-dont-my-udev-rules-work-inside-of-a-running-docker-container)

kernel 管理/dev/xx 的方式，首先在用户态有udev进程负责接收kernel发来的uevent，然后通过匹配/etc/udev/rules.d/xxx.rules规则，对/dev/xxx设备进行管理，在7u上这个用户态有个对应的服务: systemd-udevd.service,其实就是执行usr/lib/systemd/systemd-udevd，同样这个服务执行也需要ConditionPathIsReadWrite=/sys 这个条件

通过udevadm可以trigger触发kernel发送uevent 给上层的udev用户态进程，所以，可以通过udevadm可以调试udev uevent事件

```
#udevadm monitor
```

```
#udevadm trigger /dev/random --action=change
```

最终发现7u启动过程中是执行了systemd-udev-trigger去触发uevent. 这个service启动成功前提是ConditionPathIsReadWrite=/sys ,  也就是/sys 可读写，这个看似和/dev/没有什么关系，实际上，通过kernel 的udev 管理机制我们可以知道,the point of udevadm trigger is to tell the kernel to send events for all the devices that are present. It does that by writing to /sys/devices/*/*/uevent. This requires sysfs to be mounted read-write on /sys。 

通过writing  /sys/devices/xxx/uevent. 发送uevent 给 容器A和物理机，此时，因为物理机上的systemd-udevd（udev用户态程序）收到了这个信号，就会，根据物理机的udev rules规则对物理机的/dev/xxx进行重置. 这就是为什么容器获得--privileged权限后，会影响到宿主的/dev/xxx 设备的原因

```
#systemctl cat  systemd-udev-trigger
...
ConditionPathIsReadWrite=/sys

[Service]
..
ExecStart=/usr/bin/udevadm trigger --type=subsystems --action=add ; /usr/bin/udevadm trigger --type=devices --action=add
```

## 解决方法

解法1: 物理机 配置上给/dev/xxx设备配置上 这个udev rules规则
udev rules配置：
举例：/dev/random 希望开机成0777

```
#cat  /etc/udev/rules.d/70-muahao_random.rules
KERNEL=="random",  GROUP="root", MODE="0777", OPTIONS="last_rule"
```

解法2: 容器中，即使在--priviledged 权限下，也不要执行systemd-udev-trigger。
在--priviledged 权限下的容器中，将systemd-udev-trigger  停掉
＃ systemctl mask systemd-udev-trigger   这个方案可以避免这个问题，但是，还需要做测试，业务验证看关闭是否对业务有影响

## REF 
[udev 管理内核设备，文档整理的好](https://www.suse.com/zh-cn/documentation/sles11/singlehtml/book_sle_admin/cha.udev.html)

[udev 详解](http://www.cnblogs.com/sopost/archive/2013/01/09/2853200.html)

[udev rules 权威](http://www.reactivated.net/writing_udev_rules.html)

