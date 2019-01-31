---
layout: post
title: "Getting start with dbus in systemd (01) - Interface, method, path"
author: muahao
excerpt: Getting start with dbus in systemd (01) - Interface, method, path
tags:
- systemd
---

# Getting start with dbus in systemd (01)
## 基本概念
### 几个概念
dbus name: 

connetion:  如下，第一行，看到的就是 "dbus name", 有一个中心 dbus name (org.freedesktop.DBus) , 其他的每个app和 dbus-daemon 创建一个连接，就是：“connection”， 所以，我们常见的“org.freedesktop.systemd1” 不仅是一个dbus name, 也是一个 “connection”.  所以，其实，我们需要看一下systemd的代码，看看systemd的connection (org.freedesktop.systemd1) 是如何 和 “dbus-daemon” 建立连接的？

path(object): path 也是object，一个app 可能有多个object，org.freedesktop.DBus 的path就是 “/”

interface： 每个 “connection” 都有很多的 “interface”

method：每个“interface” 都有很多的 “method”

properties: 每个“interface” 都有很多的 “properties”（属性）

格式：


```                                             
                                           dbus name                      path(object)                  interface.method                   argument
#dbus-send --system --print-reply  --dest=org.freedesktop.systemd1  /org/freedesktop/systemd1 org.freedesktop.DBus.Properties.Get  string:'org.freedesktop.systemd1.Manager' string:'Version'

```

下面的输出，有一点需要注意：  第一列虽然都是bus name，但是也表示了connection含义，前面数字部分代表：建立的链接，后面的 well-know name 不代表connection，比如，systemd-但是这个app 只有在启动的时候，才会和dbus-daemon 创建一个 connection 

下面的，systemd-logind 没有创建 connection: 

```
#busctl
NAME                              PID PROCESS         USER             CONNECTION    UNIT                      SESSION    DESCRIPTION
:1.1                                1 systemd         root             :1.1          -                         -          -
:1.3                           109116 dbus-monitor    root             :1.3          sshd.service              -          -
:1.31                           30273 busctl          root             :1.31         sshd.service              -          -
net.reactivated.Fprint              - -               -                (activatable) -                         -
org.freedesktop.DBus                - -               -                -             -                         -          -
org.freedesktop.PolicyKit1          - -               -                (activatable) -                         -
org.freedesktop.hostname1           - -               -                (activatable) -                         -
org.freedesktop.import1             - -               -                (activatable) -                         -
org.freedesktop.locale1             - -               -                (activatable) -                         -
org.freedesktop.login1              - -               -                (activatable) -                         -
org.freedesktop.machine1            - -               -                (activatable) -                         -
org.freedesktop.systemd1            1 systemd         root             :1.1          -                         -          -
org.freedesktop.timedate1           - -               -                (activatable) -                         -
```

下面的systemd 创建了connection: (connection name 就是1.130 ）

```
#busctl
NAME                              PID PROCESS         USER             CONNECTION    UNIT                      SESSION    DESCRIPTION
:1.130                         115271 systemd-logind  root             :1.130        systemd-logind.service    -          -
:1.131                         115289 busctl          root             :1.131        sshd.service              -          -
:1.15                               1 systemd         root             :1.15         -                         -          -
:1.4                             1571 libvirtd        root             :1.4          libvirtd.service          -          -
:1.6                            89749 polkitd         polkitd          :1.6          polkit.service            -          -
net.reactivated.Fprint              - -               -                (activatable) -                         -
org.freedesktop.DBus                - -               -                -             -                         -          -
org.freedesktop.PolicyKit1      89749 polkitd         polkitd          :1.6          polkit.service            -          -
org.freedesktop.hostname1           - -               -                (activatable) -                         -
org.freedesktop.import1             - -               -                (activatable) -                         -
org.freedesktop.locale1             - -               -                (activatable) -                         -
org.freedesktop.login1         115271 systemd-logind  root             :1.130        systemd-logind.service    -          -
org.freedesktop.machine1            - -               -                (activatable) -                         -
org.freedesktop.systemd1            1 systemd         root             :1.15         -                         -          -
org.freedesktop.timedate1           - -               -                (activatable) -                         -

```

在： https://dbus.freedesktop.org/doc/dbus-specification.html 中 有一段介绍：

Message Bus Overview

The message bus accepts connections from one or more applications. Once connected, applications can exchange messages with other applications that are also connected to the bus.  
 
In order to route messages among connections, the message bus keeps a mapping from names to connections. Each connection has one unique-for-the-lifetime-of-the-bus name automatically assigned. Applications may request additional names for a connection. Additional names are usually "well-known names" such as "com.example.TextEditor1". When a name is bound to a connection, that connection is said to own the name.

The bus itself owns a special name, org.freedesktop.DBus, with an object located at /org/freedesktop/DBus that implements the org.freedesktop.DBus interface. This service allows applications to make administrative requests of the bus itself. For example, applications can ask the bus to assign a name to a connection.

Each name may have queued owners. When an application requests a name for a connection and the name is already in use, the bus will optionally add the connection to a queue waiting for the name. If the current owner of the name disconnects or releases the name, the next connection in the queue will become the new owner.

This feature causes the right thing to happen if you start two text editors for example; the first one may request "com.example.TextEditor1", and the second will be queued as a possible owner of that name. When the first exits, the second will take over.

Applications may send unicast messages to a specific recipient or to the message bus itself, or broadcast messages to all interested recipients. See the section called “Message Bus Message Routing” for details.



### 配置文件
/etc/dbus-1/system.conf  这个

/etc/dbus-1/session.conf

看到这个xml配置： https://thebigdoc.readthedocs.io/en/latest/dbus/system-dbus.html 

### 监听socket
```
/var/run/dbus/system_bus_socket 
```

当关闭对 “`/var/run/dbus/system_bus_socket`” 的监听后， dbus-send 就会失败，但是： “#systemctl list-unit-files” 依然可以执行成功，这个也是我奇怪的地方

```
#systemctl stop dbus.socket
#systemctl stop dbus.service
```

```
#dbus-send --system --print-reply  --dest=org.freedesktop.systemd1  /org/freedesktop/systemd1 org.freedesktop.DBus.Properties.Get  string:'org.freedesktop.systemd1.Manager' string:'Version'
Failed to open connection to "system" message bus: Failed to connect to socket /var/run/dbus/system_bus_socket: Connection refused
```



## systemd(org.freedesktop.systemd1)

### 查看connection：“org.freedesktop.systemd1” 有多少method？

```
#dbus-send --system --dest=org.freedesktop.systemd1 --type=method_call  /org/freedesktop/systemd1 --print-reply org.freedesktop.DBus.Introspectable.Introspect

--
  <method name="GetUnit">
   <arg type="s" direction="in"/>
   <arg type="o" direction="out"/>
  </method>
  <method name="GetUnitByPID">
   <arg type="u" direction="in"/>
   <arg type="o" direction="out"/>
  </method>
  <method name="LoadUnit">
   <arg type="s" direction="in"/>
   <arg type="o" direction="out"/>
  </method>
  <method name="StartUnit">
   <arg type="s" direction="in"/>
   <arg type="s" direction="in"/>
--
  </method>
  <method name="StartUnitReplace">
   <arg type="s" direction="in"/>
   <arg type="s" direction="in"/>
--
  </method>
  <method name="StopUnit">
   <arg type="s" direction="in"/>
   <arg type="s" direction="in"/>
--
```

除了“org.freedesktop.systemd1” 还有 “org.freedesktop.login1”: 

```
# dbus-send --system --dest=org.freedesktop.login1 --type=method_call  /org/freedesktop/login1 --print-reply org.freedesktop.DBus.Introspectable.Introspect
```

### 查看connection：“org.freedesktop.systemd1” 有多少interface?
其中： “org.freedesktop.DBus.Introspectable” ， “org.freedesktop.DBus.Properties” 来自于 Dbus，是一种通用的 interface

systemd 功能相关的，全部实现在 interface： “org.freedesktop.systemd1.Manager”  下的 method中.

```
#dbus-send --system --dest=org.freedesktop.systemd1 --type=method_call  /org/freedesktop/systemd1 --print-reply org.freedesktop.DBus.Introspectable.Introspect  | grep -i interface
 <interface name="org.freedesktop.DBus.Peer">
 </interface>
 <interface name="org.freedesktop.DBus.Introspectable">
 </interface>
 <interface name="org.freedesktop.DBus.Properties">
 </interface>
 <interface name="org.freedesktop.systemd1.Manager">
 </interface>
```

#### org.freedesktop.DBus.Properties 用法：

”org.freedesktop.DBus.Properties” 是一个通用的interface，其实，只要有这个interface，就会有这些method, 这个interface，是用来看interface的属性的.

“org.freedesktop.DBus.Properties” 提供了一些方法：“Get”， “GetAll”， “Set”， “PropertiesChanged”，用来专门操作 interface的 "属性"的: 

```
#dbus-send --system --dest=org.freedesktop.systemd1 --type=method_call  /org/freedesktop/systemd1 --print-reply org.freedesktop.DBus.Introspectable.Introspect

 <interface name="org.freedesktop.DBus.Properties">
  <method name="Get">
   <arg name="interface" direction="in" type="s"/>
   <arg name="property" direction="in" type="s"/>
   <arg name="value" direction="out" type="v"/>
  </method>
  <method name="GetAll">
   <arg name="interface" direction="in" type="s"/>
   <arg name="properties" direction="out" type="a{sv}"/>
  </method>
  <method name="Set">
   <arg name="interface" direction="in" type="s"/>
   <arg name="property" direction="in" type="s"/>
   <arg name="value" direction="in" type="v"/>
  </method>
  <signal name="PropertiesChanged">
   <arg type="s" name="interface"/>
   <arg type="a{sv}" name="changed_properties"/>
   <arg type="as" name="invalidated_properties"/>
  </signal>
 </interface>
```

每个interface，可能会有“property”：

```
 <interface name="org.freedesktop.systemd1.Manager">
  <property name="Version" type="s" access="read">
   <annotation name="org.freedesktop.DBus.Property.EmitsChangedSignal" value="const"/>
  </property>
```

比如： 我们来看看 “org.freedesktop.systemd1” 的 “org.freedesktop.systemd1.Manager” 的几个属性吧： 

```
#dbus-send --system --print-reply  --dest=org.freedesktop.systemd1  /org/freedesktop/systemd1 org.freedesktop.DBus.Properties.Get  string:'org.freedesktop.systemd1.Manager' string:'Version'
method return sender=:1.15 -> dest=:1.104 reply_serial=2
   variant       string "219"

```

```
#dbus-send --system --dest=org.freedesktop.systemd1 --type=method_call  /org/freedesktop/systemd1 --print-reply org.freedesktop.DBus.Properties.Get string:"org.freedesktop.systemd1.Manager" string:"UnitPath"
method return sender=:1.1 -> dest=:1.30 reply_serial=2
   variant       array [
         string "/mnt/systemd_build/etc/systemd/system"
         string "/etc/systemd/system"
         string "/run/systemd/system"
         string "/run/systemd/generator"
         string "/usr/local/lib/systemd/system"
         string "/usr/lib/systemd/system"
         string "/run/systemd/generator.late"
      ]
```

#### org.freedesktop.DBus.Manager 用法：
调用method的时候，必须要指定“interface”和“method”, 指定“路径”， 指定“--type”.

如果，你调用的是“org.freedesktop.DBus.Properties” 这个interface，可能还需要指定“参数”（指定参数的时候，还需要指定参数的 “类型:string, int...”）

比如： 

```
#dbus-send --system --dest=org.freedesktop.systemd1 --type=method_call  /org/freedesktop/systemd1 --print-reply org.freedesktop.systemd1.Manager.ListUnits
```


```
#dbus-send --system --print-reply  --dest=org.freedesktop.systemd1  /org/freedesktop/systemd1 org.freedesktop.DBus.Properties.Get  string:'org.freedesktop.systemd1.Manager' string:'Version'
method return sender=:1.15 -> dest=:1.104 reply_serial=2
   variant       string "219"

```

```
#dbus-send --system --print-reply  --dest=org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.DBus.Properties.Get string:'org.freedesktop.systemd1.Manager' string:'Features'
method return sender=:1.15 -> dest=:1.105 reply_serial=2
   variant       string "+PAM +AUDIT +SELINUX +IMA -APPARMOR +SMACK +SYSVINIT +UTMP +LIBCRYPTSETUP +GCRYPT +GNUTLS +ACL +XZ -LZ4 -SECCOMP +BLKID +ELFUTILS +KMOD +IDN"
```
## busctl
refs: http://0pointer.net/blog/the-new-sd-bus-api-of-systemd.html

```
#busctl tree org.freedesktop.login1
└─/org/freedesktop/login1
  ├─/org/freedesktop/login1/seat
  │ └─/org/freedesktop/login1/seat/seat0
  ├─/org/freedesktop/login1/session
  └─/org/freedesktop/login1/user
  
```

```
# busctl introspect org.freedesktop.login1 /org/freedesktop/login1/session
NAME                                TYPE      SIGNATURE RESULT/VALUE FLAGS
org.freedesktop.DBus.Introspectable interface -         -            -
.Introspect                         method    -         s            -
org.freedesktop.DBus.Peer           interface -         -            -
.GetMachineId                       method    -         s            -
.Ping                               method    -         -            -
org.freedesktop.DBus.Properties     interface -         -            -
.Get                                method    ss        v            -
.GetAll                             method    s         a{sv}        -
.Set                                method    ssv       -            -
.PropertiesChanged                  signal    sa{sv}as  -            -

```

```
                                                                              interface             method
#busctl call org.freedesktop.login1 /org/freedesktop/login1/session  org.freedesktop.DBus.Properties GetAll
Expected interface parameter
```
## dbus(org.freedesktop.DBus)
## dbus-daemon
首先，我们知道： dbus-send, dbus-daemon, dbus-monitor 都来自dbus这个包。

所以，dbus-send , dbus-monitor --system 监控的就是 dbus-daemon。

dbus-daemon的启动方式：

```
#systemctl cat dbus
# /usr/lib/systemd/system/dbus.service
[Unit]
Description=D-Bus System Message Bus
Requires=dbus.socket
After=syslog.target

[Service]
ExecStart=/bin/dbus-daemon --system --address=systemd: --nofork --nopidfile --systemd-activation
ExecReload=/bin/dbus-send --print-reply --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig
OOMScoreAdjust=-900

``` 

### dbus-daemon  和 org.freedesktop.DBus 之间有关系吗？ 
有的

dbus-daemon reload 方式： 

```
#/bin/dbus-send --print-reply --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig
method return sender=org.freedesktop.DBus -> dest=:1.4 reply_serial=2
```

### org.freedesktop.DBus 有哪些interface:

```
#/bin/dbus-send --print-reply --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.Introspectable.Introspect  | grep interface
  <interface name="org.freedesktop.DBus">
  </interface>
  <interface name="org.freedesktop.DBus.Introspectable">
  </interface>
```

### org.freedesktop.DBus 有哪些method:

看上去，大部分都在 interface: org.freedesktop.DBus 下面: 

```
#/bin/dbus-send --print-reply --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.Introspectable.Introspect
method return sender=org.freedesktop.DBus -> dest=:1.18 reply_serial=2
   string "<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.freedesktop.DBus">
    <method name="Hello">
      <arg direction="out" type="s"/>
    </method>
    <method name="RequestName">
      <arg direction="in" type="s"/>
      <arg direction="in" type="u"/>
      <arg direction="out" type="u"/>
    </method>
    <method name="ReleaseName">
      <arg direction="in" type="s"/>
      <arg direction="out" type="u"/>
    </method>
    <method name="StartServiceByName">
      <arg direction="in" type="s"/>
      <arg direction="in" type="u"/>
      <arg direction="out" type="u"/>
    </method>
    <method name="UpdateActivationEnvironment">
      <arg direction="in" type="a{ss}"/>
    </method>
    <method name="NameHasOwner">
      <arg direction="in" type="s"/>
      <arg direction="out" type="b"/>
    </method>
    <method name="ListNames">
      <arg direction="out" type="as"/>
    </method>
    <method name="ListActivatableNames">
      <arg direction="out" type="as"/>
    </method>
    <method name="AddMatch">
      <arg direction="in" type="s"/>
    </method>
    <method name="RemoveMatch">
      <arg direction="in" type="s"/>
    </method>
    <method name="GetNameOwner">
      <arg direction="in" type="s"/>
      <arg direction="out" type="s"/>
    </method>
```

执行一个method： 

报错是因为， Hello method只有在connection建立的时候才会执行； 

但是，这里还有一个问题，为什么dest: "org.freedesktop.DBus"  对应的path是:"/" 呢？ 

```
#/bin/dbus-send --print-reply --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.Hello
Error org.freedesktop.DBus.Error.Failed: Already handled an Hello message
```

## gdbus
来自： glib2

```
#gdbus introspect --system --dest org.freedesktop.systemd1 --object-path /org/freedesktop/systemd1
node /org/freedesktop/systemd1 {
  interface org.freedesktop.DBus.Peer {
    methods:
      Ping();
      GetMachineId(out s machine_uuid);
    signals:
    properties:
  };
  interface org.freedesktop.DBus.Introspectable {
    methods:
      Introspect(out s data);
    signals:
    properties:
  };
  interface org.freedesktop.DBus.Properties {
    methods:
      Get(in  s interface,
          in  s property,
          out v value);
      GetAll(in  s interface,
             out a{sv} properties);
      Set(in  s interface,
          in  s property,
          in  v value);
    signals:
      PropertiesChanged(s interface,
                        a{sv} changed_properties,
                        as invalidated_properties);
    properties:
  };
  interface org.freedesktop.systemd1.Manager {
    methods:
      GetUnit(in  s arg_0,
              out o arg_1);
```

## Debug

```
#busctl
NAME                              PID PROCESS         USER             CONNECTION    UNIT                      SESSION    DESCRIPTION
:1.1                                1 systemd         root             :1.1          -                         -          -
:1.33                           33465 dbus-monitor    root             :1.33         sshd.service              -          -
:1.36                           33689 busctl          root             :1.36         sshd.service              -          -
net.reactivated.Fprint              - -               -                (activatable) -                         -
org.freedesktop.DBus                - -               -                -             -                         -          -
org.freedesktop.PolicyKit1          - -               -                (activatable) -                         -
org.freedesktop.hostname1           - -               -                (activatable) -                         -
org.freedesktop.import1             - -               -                (activatable) -                         -
org.freedesktop.locale1             - -               -                (activatable) -                         -
org.freedesktop.login1              - -               -                (activatable) -                         -
org.freedesktop.machine1            - -               -                (activatable) -                         -
org.freedesktop.systemd1            1 systemd         root             :1.1          -                         -          -
org.freedesktop.timedate1           - -               -                (activatable) -                         -

```

当dbus-send 发送给 “org.freedesktop.systemd1” 一个 “method_call” 的时候：

注意：“1.1” 这个connection  就是 “org.freedesktop.systemd1” 这个connection， 
你会注意到， “1.1” 返回 给 “1.38” 一个reply， 但是 "buctl" 确没有看到 “1.38”， 这是因为dbus-send 执行的太快，消失了。

```
#dbus-send --system --dest=org.freedesktop.systemd1 --type=method_call  /org/freedesktop/systemd1 --print-reply org.freedesktop.DBus.Properties.Get string:"org.freedesktop.systemd1.Manager" string:"Features"
method return sender=:1.1 -> dest=:1.38 reply_serial=2
   variant       string "-PAM +AUDIT +SELINUX +IMA -APPARMOR +SMACK +SYSVINIT +UTMP -LIBCRYPTSETUP -GCRYPT -GNUTLS -ACL -XZ -LZ4 -SECCOMP +BLKID -ELFUTILS -KMOD -IDN"

```

```
#dbus-monitor --system
signal sender=org.freedesktop.DBus -> dest=(null destination) serial=82 path=/org/freedesktop/DBus; interface=org.freedesktop.DBus; member=NameOwnerChanged
   string ":1.38"
   string ""
   string ":1.38"
signal sender=org.freedesktop.DBus -> dest=(null destination) serial=83 path=/org/freedesktop/DBus; interface=org.freedesktop.DBus; member=NameOwnerChanged
   string ":1.38"
   string ":1.38"
   string ""

```

## busctl高级用法
（首先，你需要知道，busctl来自systemd，有更好的耦合，不像dbus-send, dbus-monitor）

这个和 dbus-monitor 差不多： 

```
#busctl monitor  org.freedesktop.DBus
```

```
#busctl status $pid
#busctl status 1
```
### Refs
dbus手册（必读）： https://dbus.freedesktop.org/doc/dbus-specification.html

https://blog.csdn.net/linweig/article/details/5068183


https://blog.fpmurphy.com/2013/05/exploring-systemd-d-bus-interface.html


systemd dbus: https://www.freedesktop.org/wiki/Software/systemd/dbus/

不错的中文博客： http://www.fmddlmyy.cn/text52.html

https://blog.csdn.net/ty3219/article/details/47358329
