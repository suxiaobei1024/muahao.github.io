---
layout: post
title: "How to set grub2 in centos7 ?"
author: muahao
tags:
- debug
---

# 在 CentOS 7 上设置 grub2
## 1. 开机选单是自动创建出来的

请勿尝试手动编辑开机选单，因为它是按照 `/boot/` 目录内的文件自动创建出来的。然而你可以调整 `/etc/default/grub` 档内定义的通用设置，及在 `/etc/grub.d/40_custom` 档内加入个别自定项目。

`/etc/default/grub` 档的内容如下：

```
GRUB_TIMEOUT=5
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=auto rhgb quiet"
GRUB_DISABLE_RECOVERY="true"
```

通用于所有项目的内核选项都通过 `GRUB_CMDLINE_LINUX `行来定义。举个例说，要是你想看见详细的开机消息，删除 `rhgb quiet`。要是你想看见标准的开机消息，只删除 rhgb。执行以下指令便能套用更改了的设置：


```
[root@host ~]# grub2-mkconfig -o /boot/grub2/grub.cfg
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-3.10.0-229.14.1.el7.x86_64
Found initrd image: /boot/initramfs-3.10.0-229.14.1.el7.x86_64.img
Found linux image: /boot/vmlinuz-3.10.0-229.4.2.el7.x86_64
Found initrd image: /boot/initramfs-3.10.0-229.4.2.el7.x86_64.img
Found linux image: /boot/vmlinuz-3.10.0-229.el7.x86_64
Found initrd image: /boot/initramfs-3.10.0-229.el7.x86_64.img
Found linux image: /boot/vmlinuz-0-rescue-605f01abef434fb98dd1309e774b72ba
Found initrd image: /boot/initramfs-0-rescue-605f01abef434fb98dd1309e774b72ba.img
done
```

UEFI 系统上的指令是 `grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg`

### 2. 如何定义缺省项目

若要列出系统开机时显示的所有选项，请执行以下指令：


```
[root@host ~]# awk -F\' '$1=="menuentry " {print i++ " : " $2}' /etc/grub2.cfg
0 : CentOS Linux 7 (Core), with Linux 3.10.0-229.14.1.el7.x86_64
1 : CentOS Linux 7 (Core), with Linux 3.10.0-229.4.2.el7.x86_64
2 : CentOS Linux 7 (Core), with Linux 3.10.0-229.el7.x86_64
3 : CentOS Linux 7 (Core), with Linux 0-rescue-605f01abef434fb98dd1309e774b72ba
```

又或者：

```
[root@host ~]# grep "^menuentry" /boot/grub2/grub.cfg | cut -d "'" -f2
```

缺省的项目是通过` /etc/default/grub` 档内的 `GRUB_DEFAULT` 行来定义。不过，要是 `GRUB_DEFAULT` 行被设置为 saved，这个选项便存储在 `/boot/grub2/grubenv `档内。你可以这样查看它：

```
[root@host ~]# grub2-editenv list
saved_entry=CentOS Linux (3.10.0-229.14.1.el7.x86_64) 7 (Core)
```

`/boot/grub2/grubenv` 档是不能手动编辑的。请采用以下指令：

```
[root@host ~]# grub2-set-default 2
[root@host ~]# grub2-editenv list
saved_entry=2
```


留意上述 awk 指令输出的第一个项目的编号是 0。

现在你可重新引导系统。

## 3. 修复模式及紧急模式

Linux 0-rescue-... 这个选项会令系统进入修复模式。这等同于单独用户模式。

此外，CentOS 并提供了一个紧急模式。在这模式下，systemd 引导后便会立刻出现一个指令壳。其它程序都不会被引导，而主文件系统将会以只读模式挂载。其它文件系统都不会被挂载。

要进入紧急模式，请在 grub2 的选单按 e 键来编辑设置。然后在内核选项的末端加入 `systemd.unit=emergency.target`

[如果你与 systemd 关系良好 :-) 你可以在` /usr/lib/systemd/system/emergency.service` 档内查看紧急模式时发生什么事情。]

## 4. Stage 1.5（core.img）的收录位置

grub／grub2 的文件都位于 /boot 文件系统内。在一个传统（非 UEFI）的 BIOS 环境下，首先会装入一个开机映像（grub 是 stage1，grub2 是 boot.img），接著是装入 stage 1.5（grub2 是 core.img），它会引导 /boot 文件系统内的程序。stage 1.5 的收录位置可以是紧接 MBR，或在 /boot 文件系统的分区内。在 CentOS 7，缺省的位置是紧接 MBR。见 此图像。
