---
layout: post
title: "The relation between systemd-journald and syslog on Centos7"
author: Ahao Mu
excerpt: The relation between systemd-journald and syslog on Centos7
tags:
- Linux
---

#前言
7u上出现了 systemd-journald，其实还是很好用的，但是我们依然要使用第三方日志program，比如syslog-ng,rsyslog,有了它们，我们才有/var/log/xxx,这些熟悉的文件！！！
那么日志是如何从产生到第三方log program的呢？
我们看日志的地方有很多，dmesg，cat /proc/dmesg,journalctl -f ,cat /var/log/message,它们之间有什么关联？
下面举个例子

#7u是如何将日志转发到syslog-ng的？
阅读man手册，快速了解权威
```
#man journald.conf
Storage=
           Controls where to store journal data. One of "volatile", "persistent", "auto" and "none". If "volatile", journal log data will be stored only in memory, i.e. below the /run/log/journal hierarchy
           (which is created if needed). If "persistent", data will be stored preferably on disk, i.e. below the /var/log/journal hierarchy (which is created if needed), with a fallback to /run/log/journal
           (which is created if needed), during early boot and if the disk is not writable.  "auto" is similar to "persistent" but the directory /var/log/journal is not created if needed, so that its
           existence controls where log data goes.  "none" turns off all storage, all log data received will be dropped. Forwarding to other targets, such as the console, the kernel log buffer, or a syslog
           socket will still work however. Defaults to "auto".

ForwardToSyslog=, ForwardToKMsg=, ForwardToConsole=, ForwardToWall=
           Control whether log messages received by the journal daemon shall be forwarded to a traditional syslog daemon, to the kernel log buffer (kmsg), to the system console, or sent as wall messages to
           all logged-in users. These options take boolean arguments. If forwarding to syslog is enabled but nothing reads messages from the socket, forwarding to syslog has no effect. By default, only
           forwarding to wall is enabled. These settings may be overridden at boot time with the kernel command line options "systemd.journald.forward_to_syslog=", "systemd.journald.forward_to_kmsg=",
           "systemd.journald.forward_to_console=", and "systemd.journald.forward_to_wall=". When forwarding to the console, the TTY to log to can be changed with TTYPath=, described below

FORWARDING TO TRADITIONAL SYSLOG DAEMONS
       Journal events can be transferred to a different logging daemon in two different ways. In the first method, messages are immediately forwarded to a socket (/run/systemd/journal/syslog), where the
       traditional syslog daemon can read them. This method is controlled by ForwardToSyslog= option. In a second method, a syslog daemon behaves like a normal journal client, and reads messages from the
       journal files, similarly to journalctl(1). In this method, messages do not have to be read immediately, which allows a logging daemon which is only started late in boot to access all messages since
       the start of the system. In addition, full structured meta-data is available to it. This method of course is available only if the messages are stored in a journal file at all. So it will not work if
       Storage=none is set. It should be noted that usually the second method is used by syslog daemons, so the Storage= option, and not the ForwardToSyslog= option, is relevant for them.
```

阅读了man手册，结合网上的配置，可以知道 /etc/systemd/journald.conf 这个文件是要修改的，如下，是一个很好的配置
```

[root@localhost-2 /home/ahao.mah]
#vim /etc/systemd/journald.conf
[Journal]
Storage=auto
#Compress=yes
#Seal=yes
#SplitMode=uid
#SyncIntervalSec=5m
#RateLimitInterval=30s
#RateLimitBurst=1000
#SystemMaxUse=
#SystemKeepFree=
#SystemMaxFileSize=
#RuntimeMaxUse=
#RuntimeKeepFree=
#RuntimeMaxFileSize=
#MaxRetentionSec=
#MaxFileSec=1month
ForwardToSyslog=yes
ForwardToKMsg=no   #其实这个转发是转发到/dev/kmsg,然后dimes命令从这里读日志，所以，这个参数打开，dmesg中将看到auth，su等用户态日志！
ForwardToConsole=no  #这个关闭，conman登陆后，console上打印kernel日志是正常的表现，如果，这个参数设置为yes，console上有个各种sudo日志，影响操作
#ForwardToWall=yes
#TTYPath=/dev/console
MaxLevelStore=debug
MaxLevelSyslog=debug
MaxLevelKMsg=notice
MaxLevelConsole=info
#MaxLevelWall=emerg
```
修改完之后，需要重启systemd-journald

如下是对syslog和systemd-journald的实现逻辑的理解，言简意赅
```
当ForwardToSyslog=yes 开启， the first method, messages are immediately forwarded to a socket (/run/systemd/journal/syslog), where the traditional syslog daemon can read them. This method is controlled by ForwardToSyslog= option

[root@localhost-2 /home/ahao.mah]
#lsof /run/systemd/journal/syslog
COMMAND      PID USER   FD   TYPE             DEVICE SIZE/OFF     NODE NAME
systemd        1 root   26u  unix 0xffff8817bc356400      0t0 32171674 /run/systemd/journal/syslog
syslog-ng 130161 root    3u  unix 0xffff8817bc356400      0t0 32171674 /run/systemd/journal/syslog

```
#/proc/kmsg ；/dev/kmsg；dmesg关系？
##通俗的讲：
1.日志其实是往 /dev/kmsg中打的，不能往/proc/kmsg中打
2.读日志是从/proc/kmsg中中读，不是从dev/kmsg中读
3.dmesg - print or control the kernel ring buffer
##Consider following flow 
```
(Kernel ring buffer)  -->  (do_syslog function)  -->  (syslog system call)  and  (/proc/kmsg) -->  (glibc syslog api)  -->  (dmesg) and (other applications)

1. Kernel provides do_syslog function to access ring buffer
2. /proc/kmsg and syslog system call calls this function to get data and return to user space
3. glibc provides syslog api as a wrapper for syslog system call
4. applications such as dmesg uses this api to access ring buffer
```
![screenshot](http://img2.tbcdn.cn/L1/461/1/71820100529f79f79670ff6077212652c0c9d2a8)

#what is /dev/kmsg?
The /dev/kmsg character device node provides userspace access to the kernel's printk buffer.
#what is /proc/kmsg?
This file is used to hold messages generated by the kernel. These messages are then picked up by other programs, such as /sbin/klogd or /bin/dmesg.
what is the difference between /proc/kmsg and dmsg?
```
[root@localhost-2 /home/ahao.mah]
#echo 'MAH------kernel message' > /dev/kmsg

[root@localhost-2 /root/rpmbuild/SOURCES]
#cat /proc/kmsg
<12>[2986996.810260] MAH------kernel message

[root@localhost-2 /home/ahao.mah]
#dmesg -T | tail -1
[Thu Jul 28 10:33:02 2016] MAH------kernel message
```

![screenshot](http://img4.tbcdn.cn/L1/461/1/e63673df68d71c72b8c8e5bde5590c47941ecfb3)

#What are the concepts of “kernel ring buffer”, “user level”, “log level”?
I often saw the words "kernel ring buffer", "user level", "log level" and some other words appear together. e.g.
/var/log/dmesg Contains kernel ring buffer information.
/var/log/kern.log Contains only the kernel's messages of any loglevel
/var/log/user.log Contains information about all user level logs

Yes, all of this has to do with logging. No, none of it has to do with runlevel or "protection ring".
The kernel keeps its logs in a ring buffer. The main reason for this is so that the logs from the system startup get saved until the syslog daemon gets a chance to start up and collect them. Otherwise there would be no record of any logs prior to the startup of the syslog daemon. The contents of that ring buffer can be seen at any time using the dmesg command, and its contents are also saved to /var/log/dmesg just as the syslog daemon is starting up.
All logs that do not come from the kernel are sent as they are generated to the syslog daemon so they are not kept in any buffers. The kernel logs are also picked up by the syslog daemon as they are generated but they also continue to be saved (unnecessarily, arguably) to the ring buffer.
The log levels can be seen documented in the syslog(3) manpage and are as follows:
* LOG_EMERG: system is unusable
* LOG_ALERT: action must be taken immediately
* LOG_CRIT: critical conditions
* LOG_ERR: error conditions
* LOG_WARNING: warning conditions
* LOG_NOTICE: normal, but significant, condition
* LOG_INFO: informational message
* LOG_DEBUG: debug-level message
Each level is designed to be less "important" than the previous one. A log file that records logs at one level will also record logs at all of the more important levels too.
The difference between /var/log/kern.log and /var/log/mail.log (for example) is not to do with the level but with the facility, or category. The categories are also documented on the manpage.


#7u上syslog-ng是否需额外配置kmsg？
##7u上是否需要在/etc/syslog-ng/syslog-ng.conf中：将 file ("/proc/kmsg" program_override("kernel: ")); 参数打开？
```
A：
source s_sys {
# Source additional configuration files (.conf extension only)
#   file ("/proc/kmsg" program_override("kernel: "));
    system();
    internal();
};

B：
source s_sys {
# Source additional configuration files (.conf extension only)
    file ("/proc/kmsg" program_override("kernel: "));
    system();
    internal();
};
```
验证发现，无论是否添加这个参数，
```
[root@localhost-2 /home/ahao.mah]
#echo "----ell--"  >/dev/kmsg

[root@localhost-2 /home/ahao.mah]
#journalctl -f
[root@localhost-2 /home/ahao.mah]
#tail /var/log/messages -f
```
都可以看到日志！！！！

但是#echo "----ell--"  >/dev/kmsg 不会往 /var/log/kern 中打印日志！！！因为，#echo "----ell--"  >/dev/kmsg 实在往“kernel ring buffer”中打日志！！


#dmesg  kern syslog-ng 时间不正确
/var/log/messages 或者 /var/log/kern时间错误的问题
官方文档参考：
https://www.balabit.com/sites/default/files/documents/syslog-ng-ose-latest-guides/en/syslog-ng-ose-guide-admin/html/reference-options.html
keep_timestamp()
Description: Specifies whether syslog-ng should accept the timestamp received from the sending application or client. If disabled, the time of reception will be used instead. This option can be specified globally, and per-source as well. The local setting of the source overrides the global option if available.

解决办法：
```
vim /etc/syslog-ng/syslog-ng.conf
添加参数：
keep_timestamp(no);
```

