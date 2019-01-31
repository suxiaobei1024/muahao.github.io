---
layout: post
title: "Getting start with dbus in systemd (04) - How to build centos systemd"
author: muahao
tags:
- systemd
---

## 快速编译
### 首先，需要checkout到v225之前的分支，之后的systemd版本3.10的kernel版本已经不够了。

```
[root@localhost /home/ahao.mah/systemd]
#git branch
  jiangyi-dev
  master
* v225_jiangyi
```

### 安装依赖
根据经验，需要安装如下rpm包：

```
[root@localhost /home/ahao.mah/systemd]
#ll ../systemd_build/dep/
total 568
-rw-r--r-- 1 root     root  309336 Oct 18 10:49 gperf-3.0.4-8.1.alios7.x86_64.rpm
-rw-r--r-- 1 ahao.mah users  71780 Nov 28 23:54 libblkid-devel-2.23.2-27.2.alios7.x86_64.rpm
-rw-r--r-- 1 ahao.mah users  25444 Nov 28 23:54 libcap-devel-2.22-8.2.alios7.x86_64.rpm
-rw-r--r-- 1 ahao.mah users  72456 Nov 28 23:54 libmount-devel-2.23.2-27.2.alios7.x86_64.rpm
-rw-r--r-- 1 ahao.mah users  90188 Nov 28 23:54 libuuid-devel-2.23.2-27.2.alios7.x86_64.rpm
```

###  sh autogen.sh 自动生成Makefile
根据经验，需要把如下注释：

```
1. #vim configure.ac

if test "x${have_gcrypt}" != xno ; then
#        AM_PATH_LIBGCRYPT(
#                [1.4.5],
#                [have_gcrypt=yes],
#                [if test "x$have_gcrypt" = xyes ; then
#                        AC_MSG_ERROR([*** GCRYPT headers not found.])
#                fi])


2. #vim src/libsystemd/sd-netlink/netlink-types.c
//[IFLA_BRPORT_PROXYARP]          = { .type = NETLINK_TYPE_U8 }

```
```
[root@localhost /home/ahao.mah/systemd]
#sh autogen.sh
```
### 安装libcap，并且指定libcap的头
```
# sh ../systemd_build/muahao_build_systemd.sh
```
### 开始编译
```
[root@localhost /home/ahao.mah/systemd]
#./configure --prefix=/usr/local/systemd

#make
```

## 问题清单
### Q1: configure: error: *** POSIX caps headers not found

```
[root@localhost /home/ahao.mah/systemd]
#./configure
...
checking sys/capability.h presence... no
checking for sys/capability.h... no
configure: error: *** POSIX caps headers not found
```

#### Solve 1: Need libcap-2.24.tar.gz
Download From : https://pastebin.com/9mdDTG28

```
1. 首先需要源代码
[root@localhost /home/ahao.mah/systemd_build]
#wget http://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.24.tar.xz

2. 其次需要devel包
#yum install -y libcap-devel
```
```
[root@localhost /home/ahao.mah/systemd]
#sh ../systemd_build/muahao_build_systemd.sh
```
You need export lib include path:

```
[root@localhost /home/ahao.mah/systemd]
#cat ../systemd_build/muahao_build_systemd.sh
#!/bin/sh
LIBCAP_DIR="/home/ahao.mah/systemd_build/libcap-2.24/"
#export LDFLAGS="-L${LIBCAP_DIR}/libcap -L${LIBCAP_DIR}/libattr/.libs -lattr"
export LDFLAGS="-L${LIBCAP_DIR}/libcap"
export CFLAGS="-I${LIBCAP_DIR}/libcap/include"
```
Then, configure:

```
[root@localhost /home/ahao.mah/systemd]
#./configure
```

### Q2: configure: error: *** libmount support required but libraries not found

```
checking for XKBCOMMON... no
checking for BLKID... no
checking for MOUNT... no
configure: error: *** libmount support required but libraries not found
```

### Solve 2:
```
[root@localhost /home/ahao.mah/systemd]
#yum install -y libmount-devel.x86_64
```

### Q3:
```
[root@localhost /home/ahao.mah/systemd]
#./configure
...
checking for acl_get_file in -lacl... no
./configure: line 18044: syntax error near unexpected token `newline'
./configure: line 18044: `        AM_PATH_LIBGCRYPT('
```

### Solve 3:
[http://blog.csdn.net/hjd_love_zzt/article/details/17487539](http://blog.csdn.net/hjd_love_zzt/article/details/17487539)



### Q4: config.status: error: cannot find input file: Makefile.in'
```
checking that generated files are newer than configure... done
configure: creating ./config.status
config.status: error: cannot find input file: `Makefile.in'

报错原因是：configure.ac 不知道什么情况，#automake --add-missing
就是不生成Makefile.in文件，不生成这个文件的原因可能和下面有关系：

configure.ac:84: error: required file 'src/udev/cdrom_id/Makefile.in' not found
configure.ac:84: error: required file 'src/udev/collect/Makefile.in' not found
configure.ac:84: error: required file 'src/udev/mtd_probe/Makefile.in' not found
configure.ac:84: error: required file 'src/udev/net/Makefile.in' not found
configure.ac:84: error: required file 'src/udev/scsi_id/Makefile.in' not found
configure.ac:84: error: required file 'src/udev/v4l_id/Makefile.in' not found
configure.ac:84: error: required file 'src/update-done/Makefile.in' not found
configure.ac:84: error: required file 'src/update-utmp/Makefile.in' not found
configure.ac:84: error: required file 'src/user-sessions/Makefile.in' not found
configure.ac:84: error: required file 'src/vconsole/Makefile.in' not found
configure.ac:84: error: required file 'sysctl.d/Makefile.in' not found

```


```
[root@localhost /home/ahao.mah/systemd]
#vim ./config.h

#define HAVE_DECL_IFLA_BRPORT_LEARNING_SYNC 1
```

### Q7: make[2]: *** [man/bootup.7] Error 127
```
[root@localhost /home/ahao.mah/systemd]
#make
make --no-print-directory all-recursive
Making all in .
  XSLT     man/bootup.7
/bin/sh: -o: command not found
make[2]: *** [man/bootup.7] Error 127
make[1]: *** [all-recursive] Error 1
make: *** [all] Error 2
```
## REF

[http://blog.csdn.net/caspiansea/article/details/71438575](http://blog.csdn.net/caspiansea/article/details/71438575)

[http://blog.csdn.net/CaspianSea/article/details/70418920?locationNum=6&fps=1](http://blog.csdn.net/CaspianSea/article/details/70418920?locationNum=6&fps=1)

 Important [Libcap-2.24](https://linux.cn/lfs/LFS-BOOK-7.7-systemd/chapter06/libcap.html)

[Makefile自动生成](http://blog.csdn.net/dybinx/article/details/6764874)

[makefile葵花宝典](http://www.zhimengzhe.com/linux/262182.html)

[ninja-build](https://github.com/ninja-build/ninja/releases)


### 在交叉编译systemd的时候，遇到上面的报错。

步骤是这样的：

```
export CFLAGS="-I/home/charles/code/build_systemd/libcap2-2.24/libcap/include"

export LDFLAGS="-L/home/charles/code/build_systemd/libcap2-2.24/libcap"

./configure --host=arm-linux-gnueabi
```

错误如下：

```
checking for linux/vm_sockets.h... yes
checking for library containing clock_gettime... none required
checking for library containing cap_init... no
configure: error: *** POSIX caps library not found
```

可是，caps 库文件是存在的：

```
$ ls /home/charles/code/build_systemd/libcap2-2.24/libcap/libcap.*
/home/charles/code/build_systemd/libcap2-2.24/libcap/libcap.a
/home/charles/code/build_systemd/libcap2-2.24/libcap/libcap.h
/home/charles/code/build_systemd/libcap2-2.24/libcap/libcap.pc
/home/charles/code/build_systemd/libcap2-2.24/libcap/libcap.pc.in
/home/charles/code/build_systemd/libcap2-2.24/libcap/libcap.so
/home/charles/code/build_systemd/libcap2-2.24/libcap/libcap.so.2
/home/charles/code/build_systemd/libcap2-2.24/libcap/libcap.so.2.24
```
看一下 config.log，里面有这样的错误：

```
configure:16664: result: no   configure:16671: error: *** POSIX caps library not found
```

原来，错误的原因是没有加上 -lattr.

修改如下：

```
export LDFLAGS="-L/home/charles/code/build_systemd/libcap2-2.24/libcap -L/home/charles/code/build_systemd/attr-2.4.47/libattr/.libs -lattr"
```

重新执行 configure,通过了。
