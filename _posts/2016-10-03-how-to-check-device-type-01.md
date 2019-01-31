---
layout: post
title: "Linux如何区分盘的类型"
author: muahao
tags:
- storage
---

### 基本信息
查看控制器：

```
[root@xxxx /root]
#lspci | grep -i contro
00:11.4 SATA controller: Intel Corporation C610/X99 series chipset sSATA Controller [AHCI mode] (rev 05)
03:00.0 Serial Attached SCSI controller: LSI Logic / Symbios Logic SAS3008 PCI-Express Fusion-MPT SAS-3 (rev 02)
```

查看盘使用的哪个控制器： 

```
[root@xxxx /root]
#ll /sys/block/ | grep 03:00.0
lrwxrwxrwx 1 root root 0 Jul 19 05:37 sdaa -> ../devices/pci0000:00/0000:00:03.0/0000:03:00.0/host10/port-10:0/expander-10:0/port-10:0:25/end_device-10:0:25/target10:0:25/10:0:25:0/block/sdaa
lrwxrwxrwx 1 root root 0 Jul 19 05:37 sdab -> ../devices/pci0000:00/0000:00:03.0/0000:03:00.0/host10/port-10:0/expander-10:0/port-10:0:26/end_device-10:0:26/target10:0:26/10:0:26:0/block/sdab
lrwxrwxrwx 1 root root 0 Jul 19 05:37 sdac -> ../devices/pci0000:00/0000:00:03.0/0000:03:00.0/host10/port-10:0/expander-10:0/port-10:0:27/end_device-10:0:27/target10:0:27/10:0:27:0/block/sdac
```

```
#cat /sys/block/sda/queue/rotational
1

1 表示非旋转类型的盘
```
### 1、 yum -y install smartmontools搜索
smartctl -a /dev/sda

可以看到vendor
硬盘是否打开了SMART支持
smartctl -i /dev/sda

### 2、查看硬盘的健康状况：
smartctl -H /dev/sda
### 3、详细的参数：
smartctl -A /dev/sdb
### 4、yum install hdparm
测试硬盘读写速度命令

```
#hdparm -tT /dev/sda
/dev/sda:

 Timing cached reads:   3286 MB in  1.99 seconds = 1653.51 MB/sec
 Timing buffered disk reads: 456 MB in  3.01 seconds = 151.47 MB/sec
```

### 5、或者创建个文件看速度
dd bs=1M count=128 if=/dev/zero of=test conv=fdatasync
dd if=/dev/zero of=/root/1Gb.file bs=1024 count=1000000


### SATA && SAS

* SAS比SATA要贵很多
* SATA的limit： 600MB/s

### AHCI && NVMe
* AHCI worker for HDD, but still support ssd
* Nvme based on PCI-E

Difference: 

* AHCI only handle one queue at a time with up to 32 pending commands, It's enough for slowly hdd, but not a good thing for faster SSD.
* Nvme support 65000 queue, 


### PCI-e bus
* M.2 , SATA
* Nvme (BIOS should support it)


### M.2 

接口： M.2

总线标准： SATA， PCI-E

协议： Nvme， AHCI


![](https://images2018.cnblogs.com/blog/970272/201807/970272-20180719162102278-342682141.png)

