---
layout: post
title: "Getting start with dbus in systemd (02) - How to create a private dbus-daemon"
author: muahao
tags:
- systemd
---

# Getting start with dbus in systemd (02)
## 创建一个私有的dbus-daemon (session) 
### 环境
这里我们会有两个app: app1(client)，app2(server), 然后，再启动一个“dbus-daemon （session）”

我们期望，app1 和 app2 之间的通信，可以使用 刚才启动的 “dbus-daemon”

代码在： 

```
git clone https://github.com/muahao/hello-dbus3-0.1.git
```

环境： 

* centos 7 

依赖： 

* dbus-x11-1.6.12-13.1.rhel7.x86_64  (提供dbus-launch)
* dbus-glib-0.100-7.1.rhel7.x86_64(代码实现依赖)


### 启动一个dbus-daemon (session)
方式1： 使用dbus-launch 创建一个dbus-daemon: 

```
#yum install -y dbus-x11-1:1.6.12-13.1.alios7.x86_64

#dbus-launch
DBUS_SESSION_BUS_ADDRESS=unix:abstract=/tmp/dbus-7Q7Spuq5IH,guid=079edc76e4c5c6433d3507855c5260ce
DBUS_SESSION_BUS_PID=121376
```

方式2： 手动启动

```
#DBUS_VERBOSE=1 dbus-daemon --session --print-address
unix:abstract=/tmp/dbus-jXwkggHTo2,guid=dc666ee7ba7ddf788efd8c485c526564
```

两个方式的目的，不仅仅是启动dbus-daemon, 更重要的是，获得address. 


注意，这里会反馈一个地址， `unix:abstract=/tmp/dbus-7Q7Spuq5IH,guid=079edc76e4c5c6433d3507855c5260ce`  ， 所以，你需要保证 你的环境变量 `DBUS_SESSION_BUS_ADDRESS`的值就是这个地址。

其实dbus-daemon是有地址的，而且有一个环境变量来表示它`--DBUS_SESSION_BUS_ADDRESS`，可以用命令env查看到。我们的程序，也就就是依靠这个环境变量来确认使用哪一个dbus-daemon的。

当我们登录进桌面环境的时候，系统启动脚本会调用到dbus-launch来启动一个dbus-daemon，同时会把这个dbus-daemon的地址赋予环境变量`DBUS_SESSION_BUS_ADDRESS`。


```
#ps axu | grep dbus-daemon  #新增一个dbus-daemon
dbus      91405  0.0  0.0  24312  2728 ?        Ss   Jan30   0:00 /bin/dbus-daemon --system --address=systemd: --nofork --nopidfile --systemd-activation
root     121376  0.0  0.0  24312   228 ?        Ss   10:43   0:00 /bin/dbus-daemon --fork --print-pid 4 --print-address 6 --session   
```

### 设置环境变量`DBUS_SESSION_BUS_ADDRESS `
设置环境变量`DBUS_SESSION_BUS_ADDRESS`到为刚才启动的dbus-daemon 的地址：

```
#DBUS_SESSION_BUS_ADDRESS=unix:abstract=/tmp/dbus-7Q7Spuq5IH,guid=079edc76e4c5c6433d3507855c5260ce
```

### 启动server：

这里会有一个报错： 

```
#./example-service
Couldn't connect to session bus: Unable to autolaunch a dbus-daemon without a $DISPLAY for X11
```

Fix: https://www.cnblogs.com/chutianyao/p/3770627.html

```
#eval `dbus-launch --sh-syntax`
```


### 正常运行：
server:

```
#./example-service
service running

```

client: 

```
#./example-client
sum is 1099
<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.freedesktop.DBus.Introspectable">
    <method name="Introspect">
      <arg name="data" direction="out" type="s"/>
    </method>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="Get">
      <arg name="interface" direction="in" type="s"/>
      <arg name="propname" direction="in" type="s"/>
      <arg name="value" direction="out" type="v"/>
    </method>
    <method name="Set">
      <arg name="interface" direction="in" type="s"/>
      <arg name="propname" direction="in" type="s"/>
      <arg name="value" direction="in" type="v"/>
    </method>
    <method name="GetAll">
      <arg name="interface" direction="in" type="s"/>
      <arg name="props" direction="out" type="a{sv}"/>
    </method>
  </interface>
  <interface name="org.fmddlmyy.Test.Basic">
    <method name="Add">
      <arg name="arg0" type="i" direction="in"/>
      <arg name="arg1" type="i" direction="in"/>
      <arg name="ret" type="i" direction="out"/>
    </method>
  </interface>
</node>
```

Ref: 

https://blog.csdn.net/jack0106/article/details/5588057

http://www.fmddlmyy.cn/text49.html
