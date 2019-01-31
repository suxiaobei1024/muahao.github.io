---
layout: post
title: "Linux中free命令buffer和cache的区别"
author: Ahao Mu
excerpt: Linux中free命令buffer和cache的区别
tags:
- Linux
---

## free中的buffer和cache:
[redhat对free输出的解读](https://access.redhat.com/solutions/406773#diag)

两者都是RAM中的数据。简单来说，buffer是即将要被写入磁盘的，而cache是被从磁盘中读出来的。 (free中的buffer和cach它们都是占用内存的)    

*  A buffer is something that has yet to be "written" to disk. 
* A cache is something that has been "read" from the disk and stored for later use.

#### buffer
buffer : 作为buffer cache的内存，是块设备的写缓冲区。buffer是根据磁盘的读写设计的，把分散的写操作集中进行，减少磁盘碎片和硬盘的反复寻道，从而提高系统性能。linux有一个守护进程定期清空缓冲内容（即写如磁盘），也可以通过sync命令手动清空缓冲。buffer是由各种进程分配的，被用在如输入队列等方面，一个简单的例子如某个进程要求有多个字段读入，在所有字段被读入完整之前，进程把先前读入的字段放在buffer中保存。   

#### cache
cache: 作为page cache的内存, 文件系统的cache。cache经常被用在磁盘的I/O请求上，如果有多个进程都要访问某个文件，于是该文件便被做成cache以方便下次被访问，这样可提供系统性能。cache是把读取过的数据保存起来，重新读取时若命中（找到需要的数据）就不要去读硬盘了，若没有命中就读硬盘。其中的数据会根据读取频率进行组织，把最频繁读取的内容放在最容易找到的位置，把不再读的内容不断往后排，直至从中删除。　　如果 cache 的值很大，说明cache住的文件数很多。如果频繁访问到的文件都能被cache住，那么磁盘的读IO bi会非常小。


### el6:
1. free 命令，在el6 el7上的输出是不一样的；
2. 对于el6 ，看真正的有多少内存是free的，应该看 free的第二行！！！

```
[root@Linux ~]# free
             total       used       free     shared    buffers    cached
Mem:       8054344    1834624    6219720          0      60528    369948
-/+ buffers/cache:    1404148    6650196
Swap:       524280        144     524136
```

#### 第1行:
total 内存总数: 8054344
used 已经使用的内存数: 1834624
free 空闲的内存数: 6219720
shared 当前已经废弃不用，总是0
buffers Buffer Cache内存数: 60528 （缓存文件描述信息）
cached Page Cache内存数: 369948 （缓存文件内容信息）

关系：total = used + free

#### 第2行：
-/+ buffers/cache的意思相当于：
-buffers/cache 的内存数：1404148 (等于第1行的 used - buffers - cached)
+buffers/cache 的内存数：6650196 (等于第1行的 free + buffers + cached)

可见-buffers/cache反映的是被程序实实在在吃掉的内存，而+buffers/cache反映的是可以使用的内存总数。


#### 释放掉被系统cache占用的数据:
如何释放cache，这里有两个方法：

1. 手动执行sync命令（描述：sync 命令运行 sync 子例程。如果必须停止系统，则运行sync 命令以确保文件系统的完整性。sync 命令将所有未写的系统缓冲区写到磁盘中，包含已修改的 i-node、已延迟的块 I/O 和读写映射文件）

2.  ```echo 3 > /proc/sys/vm/drop_caches```

有关/proc/sys/vm/drop_caches的用法在下面进行了说明:

/proc/sys/vm/drop_caches (since Linux 2.6.16)
Writing to this file causes the kernel to drop clean caches,dentries and inodes from memory, causing that memory to become free.
To free pagecache, use echo 1 > /proc/sys/vm/drop_caches;
to free dentries and inodes, use echo 2 > /proc/sys/vm/drop_caches;
to free pagecache, dentries and inodes, use echo 3 > /proc/sys/vm/drop_caches.
Because this is a non-destructive operation and dirty objects are not freeable, the user should run sync first.


```
echo 3>/proc/sys/vm/drop_caches
```

### el7
```
[root@jiangyi01.sqa.zmf /home/ahao.mah]
#free -lm
              total        used        free      shared  buff/cache   available
Mem:          96479        6329       84368         201        5781       89491
Low:          96479       12110       84368
High:             0           0           0
Swap:          2047        2047           0
```

```
[root@jiangyi01.sqa.zmf /home/ahao.mah]
#free -k;cat /proc/meminfo  | grep MemAvailable
              total        used        free      shared  buff/cache   available
Mem:       98795000     6481796    86390012      206496     5923192    91638016
Swap:       2097148     2096352         796
MemAvailable:   91638016 kB
```
shared :  Memory used (mostly) by tmpfs (Shmem in /proc/meminfo, available on kernels 2.6.32, displayed as zero if not available)

total = used + free + buff/cache 

available = free + buff/cache(部分)

el7中free的available其实对应：```cat /proc/meminfo  | grep MemAvailable```

Estimation of how much memory is available for starting new applications, without swapping. Unlike the data provided
by the cache or free fields, this field takes into account page cache and also that not all reclaimable memory slabs
will be reclaimed due to items being in use (MemAvailable in /proc/meminfo, available on kernels 3.14, emulated on
kernels 2.6.27+, otherwise the same as free)

## 理解buffer和cache
我们可以使用dd命令去测试

首先生成一个1G的大文件

```
[root@localhost /home/ahao.mah]
#dd if=/dev/zero of=bigfile bs=1M count=1000
1000+0 records in
1000+0 records out
1048576000 bytes (1.0 GB) copied, 1.71586 s, 611 MB/s
```

```
[root@localhost /home/ahao.mah]
#du -sh bigfile
1001M	bigfile
```

清空缓存

```
[root@localhost /home/ahao.mah]
#echo 3 | tee /proc/sys/vm/drop_caches
3
```

```
[root@localhost /home/ahao.mah]
#free -m
             total       used       free     shared    buffers     cached
Mem:         96839       1695      95144          0          6         46
-/+ buffers/cache:       1642      95196
Swap:         2047          0       2047
```

读入这个文件，测试消耗的时间


```
[root@localhost /home/ahao.mah]
#time cat bigfile > /dev/null

real	0m6.770s
user	0m0.005s
sys	0m0.477s
```

```
[root@localhost /home/ahao.mah]
#free -m
             total       used       free     shared    buffers     cached
Mem:         96839       2709      94130          0         10       1051
-/+ buffers/cache:       1647      95192
Swap:         2047          0       2047
```

再次读入该文件，测试消耗的时间

```
[root@localhost /home/ahao.mah]
#time cat bigfile > /dev/null

real	0m0.235s
user	0m0.005s
sys	0m0.230s
```

对比，有了cache缓存后，第二次读的速度提高了28倍，这就是cache的力量

```
[root@localhost /home/ahao.mah]
#echo "scale=3;6770/235" |bc
28.808

```
