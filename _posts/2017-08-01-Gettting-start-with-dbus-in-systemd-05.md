---
layout: post
title: "Getting start with dbus in systemd (05) - How to build upstream systemd source code"
author: muahao
tags:
- systemd
---

```
git pull origin master
./autogen.sh
./configure CFLAGS='-g -O0 -ftrapv' --libexecdir=/usr/lib --localstatedir=/var --sysconfdir=/etc --enable-lz4 --enable-compat-libs --enable-gnuefi --disable-audit --disable-ima --disable-kdbus --with-sysvinit-path= --with-sysvrcnd-path= --with-ntp-servers="0.arch.pool.ntp.org"
make
gdb journalctl
```
