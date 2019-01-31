---
layout: post
title: "如何使用swap效缓解内存压力?"
author: Ahao Mu
excerpt: 如何使用swap效缓解内存压力?
tags:
- Linux
---

不太了解底层的人对swap空间的概念也很模糊，这里我简单举例，看看swap空间的作用

### 查看当前swap空间:3个方式

```
[root@localhost /home/ahao.mah/kirin/os_diagnosis]
#swapon -s
Filename				Type		Size	Used	Priority
/dev/sda3                              	partition	2097148	0	-1
```

```
#cat /proc/swaps
Filename				Type		Size	Used	Priority
/dev/sda3                               partition	2097148	0	-1
```

```
[root@localhost /home/ahao.mah/kirin/os_diagnosis]
#free -m
              total        used        free      shared  buff/cache   available
Mem:          96479        1488       79007        4169       15983       90466
Swap:          2047           0        2047
```

### 关闭(释放)swap空间

```
[root@localhost /home/ahao.mah/kirin/os_diagnosis]
#swapoff /dev/sda3

[root@localhost /home/ahao.mah/kirin/os_diagnosis]
#free -m
              total        used        free      shared  buff/cache   available
Mem:          96479        1487       79009        4169       15982       90468
Swap:             0           0           0
```

###  一个吃内存程序：dd

```

#systemctl cat dd
# /etc/systemd/system/dd.service
[Unit]
Description=dd
ConditionFileIsExecutable=/usr/libexec/cc.py

[Service]
Type=simple
ExecStart=/usr/libexec/dd
Slice=jiangyi.slice
CPUAccounting=yes
CPUQuota=40%
MemoryAccounting=yes
MemoryMax=100M
MemoryLimit=200M
TasksAccounting=yes
BlockIOAccounting=yes

[Install]
WantedBy=multi-user.target

```


```

#cat /usr/libexec/dd
#!/usr/bin/bash
x="a"
while [ True ];do
        x=$x$x
done;
```

### 现象：dd程序立刻OOM，并且dd程序没有重启启动
```
[847607.021675] Call Trace:
[847607.024362]  [<ffffffff81637acc>] dump_stack+0x19/0x1b
[847607.029727]  [<ffffffff816329ba>] dump_header+0x8e/0x214
[847607.035264]  [<ffffffff8116c796>] ? find_lock_task_mm+0x56/0xc0
[847607.041407]  [<ffffffff8116cc2a>] oom_kill_process+0x24a/0x3b0
[847607.047462]  [<ffffffff8108341e>] ? has_capability_noaudit+0x1e/0x30
[847607.054038]  [<ffffffff811d417f>] mem_cgroup_oom_synchronize+0x50f/0x530
[847607.060955]  [<ffffffff811d3420>] ? mem_cgroup_can_attach+0x1b0/0x1b0
[847607.067615]  [<ffffffff8116d4a4>] pagefault_out_of_memory+0x14/0x90
[847607.074100]  [<ffffffff81630e15>] mm_fault_error+0x8e/0x180
[847607.079915]  [<ffffffff81643971>] __do_page_fault+0x3e1/0x420
[847607.085906]  [<ffffffff816439d3>] do_page_fault+0x23/0x80
[847607.091535]  [<ffffffff8163fcc8>] page_fault+0x28/0x30
[847607.096897] Task in /jiangyi.slice/dd.service killed as a result of limit of /jiangyi.slice/dd.service
[847607.106574] memory: usage 204800kB, limit 204800kB, failcnt 22
[847607.112629] memory+swap: usage 204800kB, limit 9007199254740991kB, failcnt 0
[847607.119907] kmem: usage 0kB, limit 9007199254740991kB, failcnt 0
[847607.126135] Memory cgroup stats for /jiangyi.slice/dd.service: cache:0KB rss:204800KB rss_huge:133120KB mapped_file:0KB swap:0KB inactive_anon:0KB active_anon:204788KB inactive_file:0KB active_file:0KB unevictable:0KB
[847607.146201] [ pid ]   uid  tgid total_vm      rss nr_ptes swapents oom_score_adj name
[847607.154528] [ 5021]     0  5021   110741    51497     115        0             0 dd
[847607.162544] Memory cgroup out of memory: Kill process 5021 (dd) [State: 0 Flags: 4202752] score 977 or sacrifice child
[847607.173585] Killed process 5021 (dd) total-vm:442964kB, anon-rss:204720kB, file-rss:1268kB

```
```
Apr 27 14:03:32 localhost systemd[1]: Started dd.
Apr 27 14:03:32 localhost systemd[1]: Starting dd...
Apr 27 14:03:35 localhost systemd[1]: dd.service: main process exited, code=killed, status=9/KILL
Apr 27 14:03:35 localhost systemd[1]: Unit dd.service entered failed state.
Apr 27 14:03:35 localhost systemd[1]: dd.service failed.
```

### 开启SWAP空间
```
[root@localhost /home/ahao.mah/kirin/os_diagnosis]
#swapon /dev/sda3

[root@localhost /home/ahao.mah/kirin/os_diagnosis]
#swapon -s
Filename				Type		Size	Used	Priority
/dev/sda3                              	partition	2097148	0	-1

[root@localhost /home/ahao.mah/kirin/os_diagnosis]
#free -m
              total        used        free      shared  buff/cache   available
Mem:          96479        1486       79009        4169       15983       90471
Swap:          2047           0        2047
```

### 现象： dd程序没有立刻OOM，而是先用SWAP空间，监控swapin swapout可以看到大量页面置换，重要的是，swap使用空间没有一直增长，也有降低。这就看拆东墙补西墙的速度了，最终，当swap空间被使用完的一瞬间，dd程序再申请内存，触发了pagefault，此时才会触发OOM，这个dd程序将被干掉！
![](http://images2015.cnblogs.com/blog/970272/201704/970272-20170427140710209-2017731227.png)

OOM瞬间：swapd使用量跌0，so si bi bo全部跌0

![](http://images2015.cnblogs.com/blog/970272/201704/970272-20170427141439272-566036388.png)

大量swapout swapin页置换

```
2017-04-27 14:07:42,PAGE_AND_SWAP_LIVE,page_in,39448.00,pages/s
2017-04-27 14:07:42,PAGE_AND_SWAP_LIVE,page_out,58680.00,pages/s
2017-04-27 14:07:42,PAGE_AND_SWAP_LIVE,swap_in,9776.00,pages/s
2017-04-27 14:07:42,PAGE_AND_SWAP_LIVE,swap_out,14646.00,pages/s
```

### 思考：OOM是在一个程序无法申请内存地址的时候才会发生，开启swap地址，可以有效缓解内存的使用。


### Swap分区空间什么时候使用

系统在什么情况或条件下才会使用Swap分区的空间呢？ 其实是Linux通过一个参数swappiness来控制的。当然还涉及到复杂的算法。

这个参数值可为 0-100，控制系统 swap 的使用程度。高数值可优先系统性能，在进程不活跃时主动将其转换出物理内存。低数值可优先互动性并尽量避免将进程转换处物理内存，并降低反应延迟。默认值为 60。
注意：这个只是一个权值，不是一个百分比值，涉及到系统内核复杂的算法。下面是关于swappiness的相关资料

The Linux 2.6 kernel added a new kernel parameter called swappiness to let administrators tweak the way Linux swaps. It is a number from 0 to 100. In essence, higher values lead to more pages being swapped, and lower values lead to more applications being kept in memory, even if they are idle. Kernel maintainer Andrew Morton has said that he runs his desktop machines with a swappiness of 100, stating that "My point is that decreasing the tendency of the kernel to swap stuff out is wrong. You really don't want hundreds of megabytes of BloatyApp's untouched memory floating about in the machine. Get it out on the disk, use the memory for something useful."

Swappiness is a property of the Linux kernel that changes the balance between swapping out runtime memory, as opposed to dropping pages from the system page cache. Swappiness can be set to values between 0 and 100 inclusive. A low value means the kernel will try to avoid swapping as much as possible where a higher value instead will make the kernel aggressively try to use swap space. The default value is 60, and for most desktop systems, setting it to 100 may affect the overall performance, whereas setting it lower (even 0) may improve interactivity (by decreasing response latency.

有两种临时修改swappiness参数的方法，系统重启后失效

```
# echo 10 > /proc/sys/vm/swappiness
```

```
#sysctl vm.swappiness=10
```

永久

```
echo 'vm.swappiness=10' >>/etc/sysctl.conf
```

### 疑问
如果有人会问是否物理内存使用到某个百分比后才会使用Swap交换空间，可以明确的告诉你不是这样一个算法，及时物理内存只剩下8M了，但是依然没有使用Swap交换空间，而另外一个例子，物理内存还剩下19G，居然用了一点点Swap交换空间。

另外调整/proc/sys/vm/swappiness这个参数，如果你没有绝对把握，就不要随便调整这个内核参数，这个参数符合大多数情况下的一个最优值。



### Swap分区大小设置
ORACLE的官方文档就推荐如下设置，这个是根据物理内存来做参考的

![](http://images2015.cnblogs.com/blog/970272/201704/970272-20170427143430131-855722039.png)


在其它博客中看到下面一个推荐设置，当然我不清楚其怎么得到这个标准的。是否合理也无从考证。可以作为一个参考。

4G以内的物理内存，SWAP 设置为内存的2倍。

4-8G的物理内存，SWAP 等于内存大小。

8-64G 的物理内存，SWAP 设置为8G。

64-256G物理内存，SWAP 设置为16G。



### SWAP的优点和缺点：
优点：

1. Provides overflow space when your memory fills up completely
2. Can move rarely-needed items away from your high-speed memory
3. Allows you to hibernate

缺点：

1. Takes up space on your hard drive as SWAP partitions do not resize dynamically
2. Can increase wear and tear to your hard drive
3. Does not necessarily improve performance (see below)

swap占用的是磁盘的空间，如果，内存充足，压根没有用上swap空间，变相的相当于浪费了磁盘空间；swap空间大小不可以动态调整

### REF

[http://www.cnblogs.com/kerrycode/p/5246383.html](http://www.cnblogs.com/kerrycode/p/5246383.html)
