---
layout: post
title: "如何使用tcpreplay回放流量测试rsyslog性能?"
author: Ahao Mu
tags:
- Linux
---

#背景
tcpreplay可以做流量回放工具，对机器进行压测，前面，蜀大大已经使用tcpreplay对dns和ntp进行了压测，今天我就用tcpreplay来测试一下rsyslog的性能。
[使用tcpreplay回放流量测试NTP性能](http://www.atatech.org/articles/51225)
[使用tcpreplay离线流量回放测试DNS](http://www.atatech.org/articles/34801)

##测试机器
####client :localhost2  
安装syslog-ng
```
[root@localhost2 /home/ahao.mah]
#rpm -q syslog-ng
syslog-ng-3.6.4-2.alios6.x86_64
```
####server:localhost1 
安装rsyslog
```
[root@localhost1 /rsyslog/work]
#rpm -q rsyslog
rsyslog-7.6.3-1.el6.x86_64
```
#client上的准备
在client上使用logger命令，模拟打包！
```
[root@localhost2 /home/ahao.mah]
#cat logger.sh
#!/bin/bash

#sudo tcpdump -i bond0 -c 3000000 -s0 host 10.97.212.32 and port 514 -w logger3000000.pcap&

declare -i i=1
while ((i<=1000))
do
    logger -p authpriv.debug -t auth_test "pam_unix(su:session): session closed for user nobody，jiangyi_test $i\n"
	let i+=1
done
```

如果你只使用logger命令，你是不能将日志打到server上的，你必须在client上安装了syslog-ng（或者rsyslog），然后指定remote的IP地址是server:localhost1 的IP地址。
```
[root@localhost2 /home/ahao.mah]
#cat /etc/syslog-ng/remote_server.conf
destination d_sys_loghost   { udp( "10.97.212.32" port(514) suppress(10)); }
```
```
#cat /etc/syslog-ng/syslog-ng.conf
source s_sys {
        file ("/proc/kmsg" program_override("kernel: "));
        unix-stream ("/dev/log");
        internal();
};

filter f_sys_auth           { facility(auth,authpriv); };

log { source(s_sys); filter(f_sys_auth);    destination(d_sys_loghost); };

```
同时，打开一个新的窗口，开始在bond0上抓包！虽然我只抓了1000个包，但是可以回放无数的包。。
```
[root@localhost2 /home/ahao.mah]
#tcpdump -i bond0 dst host 10.97.212.32 -nn -s0 -w test03.pcap -c 1000
```
然而，得到的结论,如下，却是，一个包发重复了。原因是因为我抓包的时候 -i any ,如果，我 -i bond0，就会发现一个包只发了一遍。因为bond0绑定了两个网卡。
另外，tcpdump不能看到包的内容，tshark可以看到。
```
[root@localhost2 /home/ahao.mah]
#tshark -i any dst host 10.97.212.32 and port 514 -nn -s0 -c 5
Running as user "root" and group "root". This could be dangerous.
Capturing on Pseudo-device that captures on all interfaces
  0.000000 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:35:31 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 1\n\n
  0.000874 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:35:31 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 2\n\n
  0.000882 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:35:31 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 2\n\n
  0.001655 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:35:31 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 3\n\n
  0.001664 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:35:31 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 3\n\n
5 packets captured
```
```
[root@localhost2 /home/ahao.mah]
#tshark -i bond0 dst host 10.97.212.32 and port 514 -nn -s0 -c 5
Running as user "root" and group "root". This could be dangerous.
Capturing on bond0
  0.000000 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:38:38 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 1\n\n
  0.000773 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:38:38 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 2\n\n
  0.001785 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:38:38 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 3\n\n
  0.002781 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:38:38 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 4\n\n
  0.003835 10.97.212.34 -> 10.97.212.32 Syslog AUTHPRIV.DEBUG: Mar 15 13:38:38 localhost2 auth_test: pam_unix(su:session): session closed for user nobody\357\274\214jiangyi_test 5\n\n
5 packets captured
```

###rsyslog的配置
我们先配置rsyslog如下，测测rsyslog在不使用队列的配置的时候，rsyslog的性能有多少？
注意：/var/spool/rsyslog 这个目录需要手动建立，不会自动建立。
```
[root@localhost1 /home/ahao.mah]
#cat /etc/rsyslog.conf
$ModLoad imudp.so
$ModLoad imuxsock
$ModLoad imklog

$FileCreateMode 0755
$DirCreateMode 0755
$Umask 0022
$EscapeControlCharactersOnReceive on
#$DropTrailingLFOnReception off


$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
$template SLSFormat,"%timereported:::date-rfc3339% %HOSTNAME% %timegenerated:::date-unixtimestamp% %timegenerated:::date-rfc3339% %syslogtag% [%pri-text%] %msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n"


$WorkDirectory /var/spool/rsyslog

$IncludeConfig /etc/rsyslog.d/

$DefaultRuleset Local

$InputUDPServerBindRuleset Remote
$UDPServerRun 514

$InputUDPServerBindRuleset NetConsole
$UDPServerRun 2514

```

#使用tcpreplay
前面，我们已经在localhost2上抓了正常的包，现在，在localhost2上使用tcpreplay回放，使用办法如下：
注意，使用tcpreplay的三部曲
###1. 先使用tcpprep去分类
tcpprep有很多种对包进行预先处理的办法，而且，这步是必须，最常见的办法是根据--port  去分类包。
```
#tcpprep --port --cachefile=test03_cache.pcap --pcap=test03.pcap
```
###2. 再使用tcprewrite在localhost2上去重写
(虽然，原mac目标mac，没有变，但还是要重写，我之前没有重写，发现从localhost2打到localhost1的包都idmerr了)
```
#tcprewrite --dstipmap=10.97.212.34:10.97.212.32 --infile=test03.pcap --outfile=output_test03.pcap --skipbroadcast --cachefile=test03_cache.pcap --dlt=enet --fixcsum --enet-smac=84:8f:69:ff:23:6a,84:8f:69:ff:23:6a --enet-dmac=84:8f:69:ff:23:be,84:8f:69:ff:23:be
```
###3.使用tcpreplay流量回放
```
#tcpreplay -i bond0 --loop=1 -p 1000 output_test03.pcap
```
###注意：
执行3，发现，1s就将我刚才抓的1千个包就回放完了。
-p 1000 等价于 —pps 1000
如果执行：#tcpreplay -i bond0 --loop=1 -p 2000 output_test03.pcap ，发现，0.5秒回放结束；
如果执行：#tcpreplay -i bond0 --loop=1 -p 10000 output_test03.pcap，发现，0.1秒回放结束；
可见，当-loop=1的时候，—p参数，将test03.pcap回放完就结束；
所以，—loop参数的含义仅仅是，将 output_test03.pcap文件回放几遍的含义，你完全可以定义—loop=10000，这样你有更多的时间去观察，而回放的速度，取决于-p参数，-p 1000,表示，一秒回放1000个包。-p 10000表示一秒回放10000个包。
10000000个包（loop乘以离线文件本身包含的包数量），以每秒100000个包的速度打过去，

#开始测试
##测试1
####当我回放8w个包到server上，发现server上收到了将近6.7w个包，为什么这个数据不一致呢？注意看下面第四行，可见，我回放了8w个包，但是tcpreplay自己统计的是69037.58 pps 这个速度回放的。
```
[root@localhost2 /home/ahao.mah]
#tcpreplay -i bond0 --loop=500 --pps 80000  output_test03.pcap
Actual: 502000 packets (80723500 bytes) sent in 7.02 seconds.
Rated: 11101504.2 Bps, 88.81 Mbps, 69037.58 pps
Flows: 1 flows, 0.13 fps, 251000000 flow packets, 0 non-flow
Statistics for network device: bond0
	Attempted packets:         502000
	Successful packets:        502000
	Failed packets:            0
	Truncated packets:         0
	Retried packets (ENOBUFS): 0
	Retried packets (EAGAIN):  0
```

```
[root@localhost1 /home/ahao.mah]
#tsar --udp -li 1
Time              ---------------udp--------------
Time                idgm    odgm  noport  idmerr
10/06/16-01:16:34  67.4K    3.00    0.00    0.00
10/06/16-01:16:35  67.6K    1.00    0.00    0.00
10/06/16-01:16:36  67.6K    1.00    0.00    0.00
10/06/16-01:16:37  67.6K    3.00    0.00    0.00
10/06/16-01:16:38  68.1K    0.00    0.00    0.00
10/06/16-01:16:39  67.5K    3.00    0.00    0.00
```
##测试2
####当我回放10w个包到server上，发现server上收到了将近7.9w个包,为什么这个数据不一致呢？注意看下面第四行，可见，我回放了10w个包，但是tcpreplay自己统计的是79729.68 pps这个速度回放的。
```
[root@localhost2 /home/ahao.mah]
#tcpreplay -i bond0 --loop=500 --pps 100000  output_test03.pcap
Actual: 502000 packets (80723500 bytes) sent in 6.02 seconds.
Rated: 12820834.5 Bps, 102.56 Mbps, 79729.68 pps
Flows: 1 flows, 0.15 fps, 251000000 flow packets, 0 non-flow
Statistics for network device: bond0
	Attempted packets:         502000
	Successful packets:        502000
	Failed packets:            0
	Truncated packets:         0
	Retried packets (ENOBUFS): 0
	Retried packets (EAGAIN):  0
```
```
[root@localhost1 /home/ahao.mah]
#tsar --udp -li 1
Time              ---------------udp--------------
Time                idgm    odgm  noport  idmerr
10/06/16-01:19:42  78.3K    0.00    0.00    0.00
10/06/16-01:19:43  78.1K    0.00    0.00    0.00
10/06/16-01:19:44  78.2K    0.00    0.00    0.00
10/06/16-01:19:45  78.2K    0.00    0.00    0.00
10/06/16-01:19:46  77.9K    0.00    0.00    0.00
```
##测试3
####当我在命令行中指定以每秒50w个包回放过去，实际上tcpreplay是以229947.55 pps的速度回放到server上的，此时流量23w/s.稍微有点丢包
```
[root@localhost2 /home/ahao.mah]
#tcpreplay -i bond0 --loop=50000 --pps 500000  output_test03.pcap
^C User interrupt...
sendpacket_abort
Actual: 44976765 packets (7232434003 bytes) sent in 195.05 seconds.
Rated: 36976437.3 Bps, 295.81 Mbps, 229947.55 pps
Flows: 1 flows, 0.00 fps, 2014824141705 flow packets, 0 non-flow
Statistics for network device: bond0
	Attempted packets:         44976765
	Successful packets:        44976765
	Failed packets:            0
	Truncated packets:         0
	Retried packets (ENOBUFS): 0
	Retried packets (EAGAIN):  0
```
```
[root@localhost1 /home/ahao.mah]
Time                idgm    odgm  noport  idmerr
10/06/16-01:27:46 120.0K    1.00    0.00  102.1K
10/06/16-01:27:47 220.3K    1.00    0.00    0.00
10/06/16-01:27:48 230.0K    1.00    0.00    0.00
10/06/16-01:27:49 224.1K    1.00    0.00    0.00
10/06/16-01:27:50 223.9K    2.00    0.00    0.00
10/06/16-01:27:51 224.5K    1.00    0.00    0.00
10/06/16-01:27:52 223.1K    1.00    0.00    0.00
10/06/16-01:27:53 225.3K    1.00    0.00    0.00
10/06/16-01:27:54 224.2K    1.00    0.00    0.00
10/06/16-01:27:55 224.1K    2.00    0.00    0.00
10/06/16-01:27:56 146.4K    1.00    0.00   63.2K
10/06/16-01:27:57 222.7K    1.00    0.00    7.9K
10/06/16-01:27:58 227.9K    0.00    0.00    0.00
10/06/16-01:27:59 226.4K    1.00    0.00    0.00
10/06/16-01:28:00 217.5K    1.00    0.00    4.3K
10/06/16-01:28:01 225.9K    0.00    0.00    4.1K
10/06/16-01:28:02 220.1K    1.00    0.00    0.00
```
```
[root@localhost1 /home/ahao.mah]
#top
top - 01:27:41 up 207 days, 19:04,  3 users,  load average: 12.92, 11.66, 10.74
Tasks: 282 total,   2 running, 280 sleeping,   0 stopped,   0 zombie
Cpu(s): 88.7%us,  4.6%sy,  0.0%ni,  2.2%id,  0.0%wa,  0.0%hi,  4.5%si,  0.0%st
Mem:  48994864k total, 48750584k used,   244280k free,   294892k buffers
Swap:  2097144k total,        0k used,  2097144k free, 10248460k cached

   PID USER      PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND
 62486 root      20   0 35.7g  35m 1492 R 995.7  0.1  49835,43 adns
 31317 root      20   0  339m  26m  904 S 170.4  0.1  11:55.81 rsyslogd
   760 root      20   0     0    0    0 S  2.3  0.0   0:33.46 jbd2/sda2-8
   138 root      20   0     0    0    0 S  1.7  0.0   0:03.35 kswapd0
```

##测试4
####当我在命令行中指定以每秒60w个包回放过去，实际上tcpreplay是以288956.28 pps的速度回放到server上的，此时流量23w/s.开始大量丢包。。。。

![screenshot](http://img2.tbcdn.cn/L1/461/1/df596c92903a1009eb52e226ae78e7eee5581f98.png)
```
[root@localhost1 /home/ahao.mah]
#tsar --udp -li 1
Time              ---------------udp--------------
Time                idgm    odgm  noport  idmerr
10/06/16-01:35:38 260.7K    1.00    0.00   27.2K
10/06/16-01:35:39 218.1K    1.00    0.00   67.1K
10/06/16-01:35:40 244.5K    1.00    0.00   45.2K
10/06/16-01:35:41 246.9K    1.00    0.00   22.0K
10/06/16-01:35:42 237.1K    0.00    0.00   53.8K
10/06/16-01:35:43 250.0K    1.00    0.00   21.4K
10/06/16-01:35:44 222.9K    0.00    0.00   50.1K
10/06/16-01:35:45 239.9K    1.00    0.00   42.2K
10/06/16-01:35:46 227.1K    1.00    0.00   44.7K
10/06/16-01:35:47 246.6K    0.00    0.00   38.7K
10/06/16-01:35:48 233.3K    1.00    0.00   48.7K
![screenshot](http://img4.tbcdn.cn/L1/461/1/782ec84b2df511e5defea79d5d019ce184c75499.png)
```


##前面4次测试的结论
前面4次测试，都是在rsyslog没有配置rsyslog队列的情况下的测试结果，结论大概可以认为rsyslog的可以承受22w/s的流量

##重新配置rsyslog
注意要手动创建 /var/spool/rsyslog目录
```
[root@localhost1 /home/ahao.mah]
#cat /etc/rsyslog.conf
$ModLoad imudp.so
$ModLoad imuxsock
$ModLoad imklog

$FileCreateMode 0755
$DirCreateMode 0755
$Umask 0022
$EscapeControlCharactersOnReceive on
#$DropTrailingLFOnReception off


$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
$template SLSFormat,"%timereported:::date-rfc3339% %HOSTNAME% %timegenerated:::date-unixtimestamp% %timegenerated:::date-rfc3339% %syslogtag% [%pri-text%] %msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n"



$MainMsgQueueType LinkedList
#$MainMsgQueueType Disk
$MainMsgQueueWorkerThreads 24
#20m
$MainMsgQueueSize 500000000
$MainMsgQueueFileName mainmsgqueue
$MainMsgQueueMaxFileSize 50g
$MainMsgQueueLowWaterMark  500000
$MainMsgQueueHighWaterMark 16000000
$MainMsgQueueDiscardMark  18000000
#$MainMsgWorkerThreadMinimumMessages  2000000000
$MainMsgQueueDiscardSeverity DaysLogsSyslog

$WorkDirectory /var/spool/rsyslog

$MainMsgQueueType LinkedList
$ActionQueueWorkerThreads 24
#10m
$ActionQueueSize 200000000
$ActionQueueType Disk
$ActionQueueFileName actionquene
$ActionQueueHighWatermark 6000000
$ActionQueueLowWatermark 1000
$ActionQueueMaxDiskSpace 20g
$ActionQueueMaxFileSize 200m
$ActionResumeRetryCount -1
$ActionQueueSaveOnShutdown on
$ActionQueueDiscardSeverity 8
$ActionQueueDiscardMark 10000000

$ActionQueueTimeoutEnqueue 3000
$ActionQueueDequeueBatchSize 500




$IncludeConfig /etc/rsyslog.d/
$DefaultRuleset Local

$InputUDPServerBindRuleset Remote
$UDPServerRun 514

$InputUDPServerBindRuleset NetConsole
$UDPServerRun 2514

```
##测试5
####看看添加了rsyslog队列之后，表现如何？先打50w,实际上真实速度是229182.61 (22w/s)pps
```
[root@localhost2 /home/ahao.mah]
#tcpreplay -i bond0 --loop=5000 --pps 500000  output_test03.pcap
Actual: 5020000 packets (807235000 bytes) sent in 21.09 seconds.
Rated: 36853432.2 Bps, 294.82 Mbps, 229182.61 pps
Flows: 1 flows, 0.04 fps, 25100000000 flow packets, 0 non-flow
Statistics for network device: bond0
	Attempted packets:         5020000
	Successful packets:        5020000
	Failed packets:            0
	Truncated packets:         0
	Retried packets (ENOBUFS): 0
	Retried packets (EAGAIN):  0
```
```
[root@localhost1 /rsyslog/work]
#tsar --udp -li 1
Time              ---------------udp--------------
Time                idgm    odgm  noport  idmerr
10/06/16-04:22:33 236.4K    0.00    0.00    4.0K
10/06/16-04:22:34 230.7K    0.00    0.00    9.6K
10/06/16-04:22:35 237.4K    0.00    0.00    1.1K
10/06/16-04:22:36 231.7K    0.00    0.00    6.2K
10/06/16-04:22:37 236.8K    0.00    0.00    2.8K
10/06/16-04:22:38 229.7K    0.00    0.00    0.00
10/06/16-04:22:39 230.9K    0.00    0.00    0.00
10/06/16-04:22:40 215.2K    0.00    0.00    0.00
10/06/16-04:22:41 236.4K    0.00    0.00  157.00
10/06/16-04:22:42 152.7K    0.00    0.00   61.5K
10/06/16-04:22:43  52.9K    0.00    0.00  175.4K
10/06/16-04:22:44 219.3K    0.00    0.00   21.1K
10/06/16-04:22:45 234.7K    0.00    0.00    3.0K
10/06/16-04:22:46 227.5K    0.00    0.00    0.00
10/06/16-04:22:47 240.8K    0.00    0.00    2.4K
10/06/16-04:22:48 225.8K    0.00    0.00    0.00
10/06/16-04:22:49 234.2K    0.00    0.00    0.00
10/06/16-04:22:50 238.8K    0.00    0.00    0.00
10/06/16-04:22:51 231.8K    0.00    0.00    0.00
Time              ---------------udp--------------
Time                idgm    odgm  noport  idmerr
10/06/16-04:22:52 178.0K    0.00    0.00    0.00
10/06/16-04:22:53   0.00    0.00    0.00    0.00
10/06/16-04:22:54   0.00    0.00    0.00    0.00
```
![screenshot](http://img3.tbcdn.cn/L1/461/1/09748bf947f9170f8483124ccedc67e27d01c9ca.png)

##测试6
####看看添加了rsyslog队列之后，表现如何？再打60w，实际上真实速度是300803.33 pps （30w/s）好像没有什么效果
```
[root@localhost2 /home/ahao.mah]
#tcpreplay -i bond0 --loop=5000 --pps 600000  output_test03.pcap
Actual: 5020000 packets (807235000 bytes) sent in 16.06 seconds.
Rated: 48370314.0 Bps, 386.96 Mbps, 300803.33 pps
Flows: 1 flows, 0.05 fps, 25100000000 flow packets, 0 non-flow
Statistics for network device: bond0
	Attempted packets:         5020000
	Successful packets:        5020000
	Failed packets:            0
	Truncated packets:         0
	Retried packets (ENOBUFS): 0
	Retried packets (EAGAIN):  0
```
```
[root@localhost1 /rsyslog/work]
#tsar --udp -li 1
Time              ---------------udp--------------
Time                idgm    odgm  noport  idmerr
10/06/16-04:25:24 198.6K    0.00    0.00   86.2K
10/06/16-04:25:25 239.2K    0.00    0.00   50.7K
10/06/16-04:25:26 237.0K    0.00    0.00   56.5K
10/06/16-04:25:27 239.6K    0.00    0.00   62.0K
10/06/16-04:25:28 248.4K    0.00    0.00   44.7K
10/06/16-04:25:29 251.3K    0.00    0.00   42.8K
10/06/16-04:25:30 222.0K    0.00    0.00   66.0K
10/06/16-04:25:31 235.4K    0.00    0.00   54.2K
10/06/16-04:25:32 242.7K    0.00    0.00   57.0K
10/06/16-04:25:33 232.8K    0.00    0.00   70.7K
10/06/16-04:25:34 230.7K    0.00    0.00   87.1K
10/06/16-04:25:35 240.3K    0.00    0.00   55.5K
10/06/16-04:25:36 198.2K    0.00    0.00  116.2K
10/06/16-04:25:37 192.3K    0.00    0.00  109.6K
10/06/16-04:25:38  23.7K    0.00    0.00    3.4K
10/06/16-04:25:39   0.00    0.00    0.00    0.00
10/06/16-04:25:40   0.00    0.00    0.00    0.00
```
![screenshot](http://img4.tbcdn.cn/L1/461/1/5c6fcc86483c5c2bf471a14f887fef8cd14c5d94.png)

##后两次测试结论
我没辙了，根据测试来看，rsyslog的能力基本在20w/s 左右


##关于队列
都说rsyslog的队列很强大，官网上说的也是一套一套的，但是为什么，我配置的就没有什么用呢？？如有问题，还请斧正我究竟哪里做错了？
![screenshot](http://img1.tbcdn.cn/L1/461/1/bf3b3555dc60d326984e16fbf05632cd16123396.png)
```
$MainMsgQueueType LinkedList                     # 定义队列LinkedList[FixedArray/LinkedList/Direct/Disk]
#$MainMsgQueueType Disk
$MainMsgQueueWorkerThreads 24                 #线程个数的上限
#20m
$MainMsgQueueSize 500000000                     #配置队列大小，即可以存放的日志条数。
$MainMsgQueueFileName mainmsgqueue      # 定义队列文件名
$MainMsgQueueMaxFileSize 50g                     # 定义磁盘队列文件最大50G，缺省10M

$MainMsgQueueLowWaterMark  500000
$MainMsgQueueHighWaterMark 16000000     #单位条数，超过这个值，开始使用磁盘
$MainMsgQueueDiscardMark  18000000         #单位条数，超过这个值，开始丢弃#$MainMsgWorkerThreadMinimumMessages  10000   #新工作线程启动的条件,设置1条   
$MainMsgQueueDiscardSeverity DaysLogsSyslog       #定义可丢弃日志的优先级（>=）

$WorkDirectory /var/spool/rsyslog
#$WorkDirectory /rsyslog/work

$MainMsgQueueType LinkedList
$ActionQueueWorkerThreads 24
#10m
$ActionQueueSize 200000000
$ActionQueueType Disk
$ActionQueueFileName actionquene
$ActionQueueHighWatermark 6000000
$ActionQueueLowWatermark 1000
$ActionQueueMaxDiskSpace 20g
$ActionQueueMaxFileSize 200m
$ActionResumeRetryCount -1                        # 重试次数， -1 表示无限重试
$ActionQueueSaveOnShutdown on               # rsyslog 关闭时将队列内容存盘，防止数据丢失
$ActionQueueDiscardSeverity 8
$ActionQueueDiscardMark 10000000

$ActionQueueTimeoutEnqueue 3000
$ActionQueueDequeueBatchSize 500

```


##参考
[rsyslog队列配置参考](http://blog.clanzx.net/2013/12/31/rsyslog.html)
[rsyslog队列配置参考（官方）](http://www.rsyslog.com/doc/v8-stable/concepts/queues.html)

[rsyslog队列配置](http://blog.clanzx.net/2014/04/09/rsyslog-queue.html)
http://www.rsyslog.com/doc/queues_analogy.html
http://www.rsyslog.com/doc/v8-stable/whitepapers/queues_analogy.html
