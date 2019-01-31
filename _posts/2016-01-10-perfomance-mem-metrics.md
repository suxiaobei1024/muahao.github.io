---
layout: post
title: "Linux系统资源分析之 - Memory"
author: Ahao Mu
tags:
- Linux
---

## 内存
这里的讲到的 “内存” 包括物理内存和虚拟内存，虚拟内存（Virtual Memory）把计算机的内存空间扩展到硬盘，物理内存（RAM）和硬盘的一部分空间（SWAP）组合在一起作为虚拟内存为计算机提供了一个连贯的虚拟内 存空间，好处是我们拥有的内存 ”变多了“，可以运行更多、更大的程序，坏处是把部分硬盘当内存用整体性能受到影响，硬盘读写速度要比内存慢几个数量级，并且 RAM 和 SWAP 之间的交换增加了系统的负担。
在操作系统里，虚拟内存被分成页，在 x86 系统上每个页大小是 4KB。Linux 内核读写虚拟内存是以 “页” 为单位操作的，把内存转移到硬盘交换空间（SWAP）和从交换空间读取到内存的时候都是按页来读写的。内存和 SWAP 的这种交换过程称为页面交换（Paging），__值得注意的是 paging 和 swapping 是两个完全不同的概念__，国内很多参考书把这两个概念混为一谈，swapping 也翻译成交换，__在操作系统里是指把某程序完全交换到硬盘以腾出内存给新程序使用，和 paging 只交换程序的部分（页面）是两个不同的概念__。纯粹的 swapping 在现代操作系统中已经很难看到了，因为把整个程序交换到硬盘的办法既耗时又费力而且没必要，现代操作系统基本都是 paging 或者 paging/swapping 混合，swapping 最初是在 Unix system V 上实现的。

### 内存相关的两个内核进程     
虚拟内存管理是 Linux 内核里面最复杂的部分，要弄懂这部分内容可能需要一整本书的讲解。 在这里只介绍和性能监测有关的两个内核进程：kswapd 和 pdflush。

* kswapd daemon
	* 用来检查 ```pages_high``` 和 ```pages_low```，如果可用内存少于 ```pages_low```，kswapd 就开始扫描并试图释放 32个页面，并且重复扫描释放的过程直到可用内存大于 ```pages_high``` 为止。扫描的时候检查3件事：
		1. 如果页面没有修改，把页放到可用内存列表里；
		2. 如果页面被文件系统修改，把页面内容写到磁盘上；
		3. 如果页面被修改 了，但不是被文件系统修改的，把页面写到交换空间。

* pdflush daemon 
	* 用来同步文件相关的内存页面，把内存页面及时同步到硬盘上。比如打开一个文件，文件被导入到内存里，对文件做了修改后并保存后，内核并不马上保存文件到硬 盘，由 pdflush 决定什么时候把相应页面写入硬盘，这由一个内核参数 ```vm.dirty_background_ratio``` 来控制，比如下面的参数显示脏页面（dirty pages）达到所有内存页面10％的时候开始写入硬盘。

```
# /sbin/sysctl -n vm.dirty_background_ratio
10
```

### vmstat 

```
# vmstat 1
procs -----------memory---------- ---swap-- -----io---- --system-- -----cpu------
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 0  3 252696   2432    268   7148 3604 2368  3608  2372  288  288  0  0 21 78  1
 0  2 253484   2216    228   7104 5368 2976  5372  3036  930  519  0  0  0 100  0
 0  1 259252   2616    128   6148 19784 18712 19784 18712 3821 1853  0  1  3 95  1
 1  2 260008   2188    144   6824 11824 2584 12664  2584 1347 1174 14  0  0 86  0
 2  1 262140   2964    128   5852 24912 17304 24952 17304 4737 2341 86 10  0  0  4
•    swpd，已使用的 SWAP 空间大小，KB 为单位； 
•    free，可用的物理内存大小，KB 为单位； 
•    buff，物理内存用来缓存读写操作的 buffer 大小，KB 为单位； 
•    cache，物理内存用来缓存进程地址空间的 cache 大小，KB 为单位； 
•    si，数据从 SWAP 读取到 RAM（swap in）的大小，KB 为单位； 
•    so，数据从 RAM 写到 SWAP（swap out）的大小，KB 为单位； 
•    bi，磁盘块从文件系统或 SWAP 读取到 RAM（blocks in）的大小，block 为单位； 
•    bo，磁盘块从 RAM 写到文件系统或 SWAP（blocks out）的大小，block 为单位； 
上面是一个频繁读写交换区的例子，可以观察到以下几点： 
•    物理可用内存 free 基本没什么显著变化，swapd 逐步增加，说明最小可用的内存始终保持在 256MB X 10％ = 2.56MB 左右，当脏页达到10％的时候（vm.dirty_background_ratio ＝ 10）就开始大量使用 swap； 
•    buff 稳步减少说明系统知道内存不够了，kwapd 正在从 buff 那里借用部分内存； 
•    kswapd 持续把脏页面写到 swap 交换区（so），并且从 swapd 逐渐增加看出确实如此。根据上面讲的 kswapd 扫描时检查的三件事，如果页面被修改了，但不是被文件系统修改的，把页面写到 swap，所以这里 swapd 持续增加。
```
### 内存的使用方式
如果想对内存性能进行分析，需要只要了解内存的使用方式，更重要的是理解kernel对内存的使用和管理方式.  
最简单的命令，是free命令，但是输出中到底什么意思，很少人能说的非常的清楚，对于buffer cache，和page cache究竟有什么区别，我之前写的文章中有详细的答案[free中buffer和cache的理解](https://www.atatech.org/articles/74075)

理解了buffer 和cache的区别之后，我们就要开始思考kernel对内存的管理方式。

1. swap使用方式？ 
2. 内存回收是方式，kswapd和direct page reclaim什么时候触发？
3. 页面类型，匿名页，只读页，脏页

### 内存回收
内核内存回收的机制主要有两种：

* 一个是使用kswapd进程对内存进行周期检查，以保证平常状态下剩余内存尽可能够用。
* 另一个是直接内存回收（direct page reclaim），就是当内存分配时没有空闲内存可以满足要求时，触发直接内存回收。

内存回收主要需要进行扫描的包括anon的inactive和active以及file的inactive和active四个链表。就是说，内存回收操作主要针对的就是内存中的文件页（file cache）和匿名页。关于活跃（active）还是不活跃（inactive）的判断内核会使用lru算法进行处理并进行标记，我们这里不详细解释这个过程。

### 内存水位标记(watermark)
Linux为内存的使用设置了三种内存水位标记，high、low、min.

剩余内存在high以上表示内存剩余较多，目前内存使用压力不大；high-low的范围表示目前剩余内存存在一定压力；low-min表示内存开始有较大使用压力，剩余内存不多了；min是最小的水位标记，当剩余内存达到这个状态时，就说明内存面临很大压力。小于min这部分内存，内核是保留给特定情况下使用的，一般不会分配。内存回收行为就是基于剩余内存的水位标记进行决策的，当系统剩余内存低于watermark[low]的时候，内核的kswapd开始起作用，进行内存回收。直到剩余内存达到watermark[high]的时候停止。如果内存消耗导致剩余内存达到了或超过了watermark[min]时，就会触发直接回收（direct reclaim）。

从上文中，可以看出min的值，决定了low的值，和high的值；但是，从kernel源码中可以知道min low high之间计算关系就是：

```
 watermark[min] = min_free_kbytes换算为page单位即可，假设为min_free_pages。（因为是每个zone各有一套watermark参数，实际计算效果是根据各个zone大小所占内存总大小的比例，而算出来的per zone min_free_pages）
 watermark[low] = watermark[min] * 5 / 4
 watermark[high] = watermark[min] * 3 / 2
```

#### min
修改```min_free_kbytes```的值在这里：

```
[root@muahao_host /home/ahao.mah]
#cat /proc/sys/vm/min_free_kbytes
3145728
```


```
/proc/zoneinfo 文件中的单位是page，page的大小是4KB

[root@muahao_host /home/ahao.mah]
#cat /proc/zoneinfo  | grep min
        min      63
        min      7139
        min      779229
```

```
[root@muahao_host /home/ahao.mah]
#echo "3145728/4" |bc
786432
```

```
[root@muahao_host /home/ahao.mah]
#echo "63+7139+779229" |bc
786431
```

如上，计算出来,```/proc/sys/vm/min_free_kbytes``` 的值和zoneinfo中的值是基本一致的！！

__如下，计算min的值,也只有2GB！__

```
[root@muahao_host /home/ahao.mah]
#echo "(63+7139+779229)*4/1024/1024" |bc
2
```


#### low 
```
[root@muahao_host /home/ahao.mah]
#cat /proc/zoneinfo  | grep low
        low      78
        low      8923
        low      974036
```

```
[root@muahao_host /home/ahao.mah]
#echo "78+8923+974036" |bc
983037
```

```
[root@muahao_host /home/ahao.mah]
#echo "(78+8923+974036)*4/1024/1024" |bc
3
```

#### high
```
[root@muahao_host /home/ahao.mah]
#cat /proc/zoneinfo  | grep high | grep -v :
        high     94
        high     10708
        high     1168843
```
```
[root@muahao_host /home/ahao.mah]
#echo "(1168843+10708+94)*4/1024/1024" |bc
4

```
### 缺页中断 
Linux 利用虚拟内存极大的扩展了程序地址空间，使得原来物理内存不能容下的程序也可以通过内存和硬盘之间的不断交换（把暂时不用的内存页交换到硬盘，把需要的内 存页从硬盘读到内存）来赢得更多的内存，看起来就像物理内存被扩大了一样。事实上这个过程对程序是完全透明的，程序完全不用理会自己哪一部分、什么时候被 交换进内存，一切都有内核的虚拟内存管理来完成。当程序启动的时候，Linux 内核首先检查 CPU 的缓存和物理内存，如果数据已经在内存里就忽略，如果数据不在内存里就引起一个缺页中断（Page Fault），然后从硬盘读取缺页，并把缺页缓存到物理内存里。__缺页中断可分为主缺页中断（Major Page Fault）和次缺页中断（Minor Page Fault），要从磁盘读取数据而产生的中断是主缺页中断；数据已经被读入内存并被缓存起来，从内存缓存区中而不是直接从硬盘中读取数据而产生的中断是次 缺页中断.__
     

__上面的内存缓存区起到了预读硬盘的作用，内核先在物理内存里寻找缺页，没有的话产生次缺页中断从内存缓存里找，如果还没有发现的话就从硬盘读取__.很 显然，把多余的内存拿出来做成内存缓存区提高了访问速度，这里还有一个命中率的问题，运气好的话如果每次缺页都能从内存缓存区读取的话将会极大提高性能。 要提高命中率的一个简单方法就是增大内存缓存区面积，缓存区越大预存的页面就越多，命中率也会越高。下面的 time 命令可以用来查看某程序第一次启动的时候产生了多少主缺页中断和次缺页中断： 

```
$ /usr/bin/time -v date
...
Major (requiring I/O) page faults: 1
Minor (reclaiming a frame) page faults: 260
...
```

### File Buffer Cache 
从上面的内存缓存区（也叫文件缓存区 File Buffer Cache）读取页比从硬盘读取页要快得多，所以 Linux 内核希望能尽可能产生次缺页中断（从文件缓存区读），并且能尽可能避免主缺页中断（从硬盘读），这样随着次缺页中断的增多，文件缓存区也逐步增大，直到系 统只有少量可用物理内存的时候 Linux 才开始释放一些不用的页。我们运行 Linux 一段时间后会发现虽然系统上运行的程序不多，但是可用内存总是很少，这样给大家造成了 Linux 对内存管理很低效的假象，事实上 Linux 把那些暂时不用的物理内存高效的利用起来做预存（内存缓存区）呢。下面打印的是的一台 Sun 服务器上的物理内存和文件缓存区的情况： 

```
$ cat /proc/meminfo
MemTotal:      8182776 kB
MemFree:       3053808 kB
Buffers:        342704 kB
Cached:        3972748 kB
```

这台服务器总共有 8GB 物理内存（MemTotal），3GB 左右可用内存（MemFree），343MB 左右用来做磁盘缓存（Buffers），4GB 左右用来做文件缓存区（Cached），可见 Linux 真的用了很多物理内存做 Cache，而且这个缓存区还可以不断增长。 



### 页面类型
* Read pages只读页（或代码页）
	* 那些通过主缺页中断从硬盘读取的页面，包括不能修改的静态文件、可执行文件、库文件等。当内核需要它们的时候把它们读到 内存中，当内存不足的时候，内核就释放它们到空闲列表，当程序再次需要它们的时候需要通过缺页中断再次读到内存。 
* Dirty pages，脏页
	* 指那些在内存中被修改过的数据页，比如文本文件等。这些文件由 pdflush 负责同步到硬盘，内存不足的时候由 kswapd 和 pdflush 把数据写回硬盘并释放内存。 
* Anonymous pages，匿名页
	* 那些属于某个进程但是又和任何文件无关联，不能被同步到硬盘上，内存不足的时候由 kswapd 负责将它们写到交换分区并释放内存。

### 回收方式
1. 匿名页-> swap
2. 脏页->回写磁盘，或者清空

这样看来，内存回收这个行为会对两种内存的使用进行回收，一种是anon的匿名页内存，主要回收手段是swap，另一种是file-backed的文件映射页，主要的释放手段是写回和清空。因为针对file based的内存，没必要进行交换，其数据原本就在硬盘上，回收这部分内存只要在有脏数据时写回，并清空内存就可以了，以后有需要再从对应的文件读回来。内存对匿名页和文件缓存一共用了四条链表进行组织，回收过程主要是针对这四条链表进行扫描和操作。

### swap使用方式
创建swap文件

```
[root@localhost /home/ahao.mah]
#dd if=/dev/zero of=./swapfile bs=1M count=8G
dd: error writing ‘./swapfile’: No space left on device
3700+0 records in
3699+0 records out
3879469056 bytes (3.9 GB) copied, 40.8418 s, 95.0 MB/s

[root@localhost /home/ahao.mah]
#mkswap swapfile
Setting up swapspace version 1, size = 3788540 KiB
no label, UUID=e013109b-2b25-4816-908a-8c8ee6c5a889
```
启动swap文件

```
[root@localhost /home/ahao.mah]
#swapon swapfile
swapon: /home/ahao.mah/swapfile: insecure permissions 0644, 0600 suggested.

[root@localhost /home/ahao.mah]
#swapon -s
Filename				Type		Size	Used	Priority
/dev/sda3                              	partition	2097148	4	-1
/home/ahao.mah/swapfile                	file	3788540	0	-2
```

关闭swap文件

```
[root@localhost /home/ahao.mah]
#swapoff swapfile

[root@localhost /home/ahao.mah]
#swapon -s
Filename				Type		Size	Used	Priority
/dev/sda3                              	partition	2097148	4	-1

```
在使用多个swap分区或者文件的时候，还有一个优先级的概念（Priority）。在swapon的时候，我们可以使用-p参数指定相关swap空间的优先级，值越大优先级越高，可以指定的数字范围是－1到32767。内核在使用swap空间的时候总是先使用优先级高的空间，后使用优先级低的。当然如果把多个swap空间的优先级设置成一样的，那么两个swap空间将会以轮询方式并行进行使用。如果两个swap放在两个不同的硬盘上，相同的优先级可以起到类似RAID0的效果，增大swap的读写效率。另外，编程时使用mlock()也可以将指定的内存标记为不会换出，具体帮助可以参考man 2 mlock。

### 内存碎片
查看内存碎片的程度，可以通过这个文件来略知一二.


This file is used primarily for diagnosing memory fragmentation issues. Using the buddy algorithm, each column represents the number of pages of a certain order (a certain size) that are available at any given time. For example, for zone DMA (direct memory access), ```there are 90 of 2^(0*PAGE_SIZE) chunks of memory. Similarly, there are 6 of 2^(1*PAGE_SIZE) chunks, and 2 of 2^(2*PAGE_SIZE) ```chunks of memory available.

The DMA row references the first 16 MB on a system, the HighMem row references all memory greater than 4 GB on a system, and the Normal row references all memory in between.

The following is an example of the output typical of /proc/buddyinfo:

```
Node 0, zone      DMA     90      6      2      1      1      ... 
Node 0, zone   Normal   1650    310      5      0      0      ... 
Node 0, zone  HighMem      2      0      0      1      1      ...
```
```
[root@localhost /home/ahao.mah]
#cat /proc/buddyinfo
Node 0, zone      DMA      1      1      1      0      2      1      1      0      1      1      3
Node 0, zone    DMA32   4035   2085    515     96     59     29     10     11     11     10    331
Node 0, zone   Normal  16248  61875  27323  10011   3305   1043    529    220    109     70  19783
```
### overcommit相关的参数
要了解这类参数首先要理解什么是committed virtual memory？使用版本管理工具的工程师都熟悉commit的含义，就是向代码仓库提交自己更新的意思，对于这个场景，实际上就是各个进程提交自己的虚拟地址空间的请求。虽然我们总是宣称每个进程都有自己独立的地址空间，但素，这些地址空间都是虚拟地址，就像是镜中花，水中月。当进程需要内存时（例如通过brk分配内存），进程从内核获得的仅仅是一段虚拟地址的使用权，而不是实际的物理地址，进程并没有获得物理内存。实际的物理内存只有当进程真的去访问新获取的虚拟地址时，产生“缺页”异常，从而进入分配实际物理地址的过程，也就是分配实际的page frame并建立page table。之后系统返回产生异常的地址，重新执行内存访问，一切好象没有发生过。因此，看起来虚拟内存和物理内存的分配被分割开了，这是否意味着进程可以任意的申请虚拟地址空间呢？也不行，毕竟virtual memory需要physical memory做为支撑，如果分配了太多的virtual memory，和物理内存不成比例，对性能会有影响。对于这个状况，我们称之为overcommit。


```
[root@localhost /home/ahao.mah]
#ll /proc/sys/vm/overcommit_*
-rw-r--r-- 1 root root 0 Mar 11 04:29 /proc/sys/vm/overcommit_kbytes
-rw-r--r-- 1 root root 0 Mar 10 15:56 /proc/sys/vm/overcommit_memory
-rw-r--r-- 1 root root 0 Mar 11 04:29 /proc/sys/vm/overcommit_ratio

```
overcommit_memory这个参数就是用来控制内核对overcommit的策略。该参数可以设定的值包括：

```
#define OVERCOMMIT_GUESS        0 
#define OVERCOMMIT_ALWAYS        1 
#define OVERCOMMIT_NEVER        2
```

OVERCOMMIT\_ALWAYS表示内核并不限制overcommit，无论进程们commit了多少的地址空间的申请，go ahead，do what you like，只不过后果需要您自己的负责。

OVERCOMMIT_NEVER是另外的极端，永远不要overcommit。

OVERCOMMIT\_GUESS的策略和其名字一样，就是“你猜”，多么调皮的设定啊，我不太喜欢这个参数的命名，更准确的命名应该类似vm\_overcommit\_policy什么的，大概是历史的原因，linux kernel一直都是保持了这个符号。


### OOM参数
#### ```/proc/sys/vm/panic_on_oom```
```
[root@localhost /home/ahao.mah]
#ll /proc/sys/vm/*oom*
-rw-r--r-- 1 root root 0 Mar 11 04:29 /proc/sys/vm/oom_dump_tasks
-rw-r--r-- 1 root root 0 Mar 11 04:29 /proc/sys/vm/oom_kill_allocating_task
-rw-r--r-- 1 root root 0 Mar 11 04:29 /proc/sys/vm/panic_on_oom
```

当kernel遇到OOM的时候，可以有两种选择：

1. 产生kernel panic（就是死给你看）。
2. 积极面对人生，选择一个或者几个最“适合”的进程，启动OOM killer，干掉那些选中的进程，释放内存，让系统勇敢的活下去。

```panic_on_oom```这个参数就是控制遇到OOM的时候，系统如何反应的。当该参数等于0的时候，表示选择积极面对人生，启动OOM killer。当该参数等于2的时候，表示无论是哪一种情况，都强制进入kernel panic。```panic_on_oom```等于其他值的时候，表示要区分具体的情况，对于某些情况可以panic，有些情况启动OOM killer。
#### ```/proc/sys/vm/oom_dump_tasks```
当系统的内存出现OOM状况，无论是panic还是启动OOM killer，做为系统管理员，你都是想保留下线索，找到OOM的root cause，例如dump系统中所有的用户空间进程关于内存方面的一些信息，包括：进程标识信息、该进程使用的total virtual memory信息、该进程实际使用物理内存（我们又称之为RSS，Resident Set Size，不仅仅是自己程序使用的物理内存，也包含共享库占用的内存），该进程的页表信息等等。拿到这些信息后，有助于了解现象（出现OOM）之后的真相。

当设定为0的时候，上一段描述的各种进程们的内存信息都不会打印出来。在大型的系统中，有几千个进程，逐一打印每一个task的内存信息有可能会导致性能问题（要知道当时已经是OOM了）。当设定为非0值的时候，在下面三种情况会调用dump_tasks来打印系统中所有task的内存状况：

1. 由于OOM导致kernel panic
2. 没有找到适合的“bad”process
3. 找适合的并将其干掉的时候

#### ```/proc/sys/vm/oom_kill_allocating_task```
系统选择了启动OOM killer，试图杀死某些进程的时候，又会遇到这样的问题：干掉哪个，哪一个才是“合适”的哪那个进程？系统可以有下面的选择：

1. 谁触发了OOM就干掉谁
2. 谁最“坏”就干掉谁

```oom_kill_allocating_task```这个参数就是控制这个选择路径的，当该参数等于0的时候选择（2），否则选择（1）当然也不能说杀就杀，还是要考虑是否用户空间进程（不能杀内核线程）、是否unkillable task（例如init进程就不能杀），用户空间是否通过设定参数（oom_score_adj）阻止kill该task。如果万事俱备，那么就调用oom\_kill\_process干掉当前进程。

#### ```oom_adj、oom_score_adj和oom_score```

1. 对某一个task进行打分（oom_score）主要有两部分组成，一部分是系统打分，主要是根据该task的内存使用情况。另外一部分是用户打分，也就是oom\_score\_adj了，该task的实际得分需要综合考虑两方面的打分。如果用户将该task的 oom\_score\_adj设定成OOM\_SCORE\_ADJ\_MIN（-1000）的话，那么实际上就是禁止了OOM killer杀死该进程。
2. 这里返回了0也就是告知OOM killer，该进程是“good process”，不要干掉它。后面我们可以看到，实际计算分数的时候最低分是1分。
3. 前面说过了，系统打分就是看物理内存消耗量，主要是三部分，RSS部分，swap file或者swap device上占用的内存情况以及页表占用的内存情况。
4. root进程有3%的内存使用特权，因此这里要减去那些内存使用量。
5. 用户可以调整oom\_score，具体如何操作呢？oom\_score\_adj的取值范围是-1000～1000，0表示用户不调整oom\_score，负值表示要在实际打分值上减去一个折扣，正值表示要惩罚该task，也就是增加该进程的oom\_score。在实际操作中，需要根据本次内存分配时候可分配内存来计算（如果没有内存分配约束，那么就是系统中的所有可用内存，如果系统支持cpuset，那么这里的可分配内存就是该cpuset的实际额度值）。oom_badness函数有一个传入参数totalpages，该参数就是当时的可分配的内存上限值。实际的分数值（points）要根据oom\_score\_adj进行调整，例如如果oom\_score\_adj设定-500，那么表示实际分数要打五折（基数是totalpages），也就是说该任务实际使用的内存要减去可分配的内存上限值的一半。

	了解了oom\_score\_adj和oom\_score之后，应该是尘埃落定了，oom\_adj是一个旧的接口参数，其功能类似oom\_score\_adj，为了兼容，目前仍然保留这个参数，当操作这个参数的时候，kernel实际上是会换算成oom\_score\_adj，有兴趣的同学可以自行了解，这里不再细述了。

 
### 虚拟内存（Virtual Memory）和驻留内存（Resident Memory）
在[https://www.atatech.org/articles/8017](https://www.atatech.org/articles/8017)中，对这两个概念有了很好的诠释，这里大概引用一些重点：

比如我们在写完一段C++程序之后都需要采用g++进行编译，这时候编译器采用的地址其实就是虚拟内存空间的地址。因为这时候程序还没有运行，何谈物理内存空间地址？凡是程序运行过程中可能需要用到的指令或者数据都必须在虚拟内存空间中。既然说虚拟内存是一个逻辑意义上（假象的）的内存空间，为了能够让程序在物理机器上运行，那么必须有一套机制可以让这些假象的虚拟内存空间映射到物理内存空间（实实在在的RAM内存条上的空间）。这其实就是操作系统中页映射表（page table）所做的事情了。内核会为系统中每一个进程维护一份相互独立的页映射表。。

虚拟内存空间和物理内存空间的相互关系，它们通过Page Table关联起来。相当于是一个映射表。

驻留内存，顾名思义是指那些被映射到进程虚拟内存空间的物理内存。

__进程的驻留内存就是进程实实在在占用的物理内存。一般我们所讲的进程占用了多少内存，其实就是说的占用了多少驻留内存而不是多少虚拟内存。因为虚拟内存大并不意味着占用的物理内存大。__

#### top命令中VIRT、RES和SHR的含义

```
   PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
 78516 root      20   0  168128  98848  98584 R  99.7  0.1   3:28.48 systemd-journal
 66493 root      20   0    4296    564    468 S  31.5  0.0  12:34.51 syslog_test
```

* VIRT
	* 包含了在已经映射到物理内存空间的部分和尚未映射到物理内存空间的部分总和。
* RES
	* 指进程虚拟内存空间中已经映射到物理内存空间的那部分的大小。所以说，看进程在运行过程中占用了多少内存应该看RES的值而不是VIRT的值。
* SHR
	* share（共享）的缩写，它表示的是进程占用的共享内存大小。进程A虚拟内存空间中的A4和进程B虚拟内存空间中的B3都映射到了物理内存空间的A4/B3部分。咋一看很奇怪。为什么会出现这样的情况呢？__其实我们写的程序会依赖于很多外部的动态库（.so），比如libc.so、libld.so等等。这些动态库在内存中仅仅会保存/映射一份，如果某个进程运行时需要这个动态库，那么动态加载器会将这块内存映射到对应进程的虚拟内存空间中__。
	* 多个进程之间通过共享内存的方式相互通信也会出现这样的情况。这么一来，__就会出现不同进程的虚拟内存空间会映射到相同的物理内存空间。这部分物理内存空间其实是被多个进程所共享的，所以我们将他们称为共享内存__，用SHR来表示。
	* 某个进程占用的内存除了和别的进程共享的内存之外就是自己的独占内存了。所以要计算进程独占内存的大小只要用RES的值减去SHR值即可。


#### 进程的smaps文件

```
[root@localhost /home/ahao.mah]
#pid=`ps axu|grep systemd-journald|grep -v grep |awk '{print $2}'`;cat /proc/$pid/s
maps
```

通过top命令我们已经能看出进程的虚拟空间大小（VIRT）、占用的物理内存（RES）以及和其他进程共享的内存（SHR）。但是仅此而已，如果我想知道如下问题：

1. 进程的虚拟内存空间的分布情况，比如heap占用了多少空间、文件映射（mmap）占用了多少空间、stack占用了多少空间？
2. 进程是否有被交换到swap空间的内存，如果有，被交换出去的大小？
3. mmap方式打开的数据文件有多少页在内存中是脏页（dirty page）没有被写回到磁盘的？
4. mmap方式打开的数据文件当前有多少页面已经在内存中，有多少页面还在磁盘中没有加载到page cahe中？
等等

以上这些问题都无法通过top命令给出答案，但是有时候这些问题正是我们在对程序进行性能瓶颈分析和优化时所需要回答的问题。所幸的是，世界上解决问题的方法总比问题本身要多得多。linux通过proc文件系统为每个进程都提供了一个smaps文件，通过分析该文件我们就可以一一回答以上提出的问题。

在smaps文件中，每一条记录（如下图2所示）表示进程虚拟内存空间中一块连续的区域。其中第一行从左到右依次表示地址范围、权限标识、映射文件偏移、设备号、inode、文件路径。详细解释可以参见understanding-linux-proc-id-maps。

```
Size：表示该映射区域在虚拟内存空间中的大小。
Rss：表示该映射区域当前在物理内存中占用了多少空间。
Shared_Clean：和其他进程共享的未被改写的page的大小。
Shared_Dirty： 和其他进程共享的被改写的page的大小。
Private_Clean：未被改写的私有页面的大小。
Swap：表示非mmap内存（也叫anonymous memory，比如malloc动态分配出来的内存）由于物理内存不足被swap到交换空间的大小。
Pss：该虚拟内存区域平摊计算后使用的物理内存大小(有些内存会和其他进程共享，例如mmap进来的)。比如该区域所映射的物理内存部分同时也被另一个进程映射了，且该部分物理内存的大小为1000KB，那么该进程分摊其中一半的内存，即Pss=500KB。
```

#### 进程maps文件

```
[root@localhost /home/ahao.mah]
#pid=`ps axu|grep systemd-journald|grep -v grep |awk '{print $2}'`;cat /proc/$pid/maps
```

```
第一列，address ：在进程地址空间中一段虚拟内存区域的起始和终止地址；
第二列，permissions ：r=read, w=write, x=execute, s=shared, p=private(copy on write)；不用说，heap和stack段不应该有x，否则就容易被xx，不过这个跟具体的版本有关；
第三列，offset ：当虚拟内存区域是由一个文件通过mmap映射时，指明该虚拟内存区域的偏移量；如果不是其它文件映射，值为0；
第四列，device ：虚拟内存区域由文件映射时文件的主设备号和次设备号；通过 cat /proc/devices
得知fd是253 device-mapper
第五列，inode ：虚拟内存区域由文件映射时文件的节点号，即inode；
第六列，pathname ：虚拟内存区域由文件映射时的文件名；
```

#### 进程的statm文件

```
[root@localhost /home/ahao.mah]
#pid=`ps axu|grep systemd-journald|grep -v grep |awk '{print $2}'`;cat /proc/$pid/statm
31691 17224 17159 64 0 90 0
```

很简单地返回7组数字，每一个的单位都是一页 （常见的是4KB），分别是：

```
[root@localhost /home/ahao.mah]
#pid=`ps axu|grep systemd-journald|grep -v grep |awk '{print $2}'`;cat /proc/$pid/statm;top |grep "systemd"
26624 10411 10346 64 0 91 0
 87956 root      20   0  106492  41644  41384 R 100.0  0.0   1:09.60 systemd-journal
     1 root      20   0  207892  22912   2444 S   0.0  0.0   2:51.54 systemd

简单计算一下，statm的第二个feild的值和top的RES值是一样的！！！

[root@localhost /home/ahao.mah]
#echo "10411*4" |bc
41644
```

statm各个feild的含义分别是：

```
size:任务虚拟地址空间大小
Resident：正在使用的物理内存大小
Shared：共享页数
Trs：程序所拥有的可执行虚拟内存大小
Lrs：被映像倒任务的虚拟内存空间的库的大小
Drs：程序数据段和用户态的栈的大小
Dt：脏页数量
```

### 瓶颈
内存的瓶颈更多的是和kernel管理内存的方式，已经内存和IO之间的关系有关。
比如： 一般当cache回收的时候，总是伴随着IO的飙升。这时候总是会触发IO的瓶颈，而不是内存的瓶颈。所以我觉得内存可能是有很多优化的地方，说瓶颈这个词不太合适。

关于swap的使用建议，针对不同负载状态的系统是不一样的。有时我们希望swap大一些，可以在内存不够用的时候不至于触发oom-killer导致某些关键进程被杀掉，比如数据库业务。也有时候我们希望不要swap，因为当大量进程爆发增长导致内存爆掉之后，会因为swap导致IO跑死，整个系统都卡住，无法登录，无法处理。这时候我们就希望不要swap，即使出现oom-killer也造成不了太大影响，但是不能允许服务器因为IO卡死像多米诺骨牌一样全部死机，而且无法登陆。跑cpu运算的无状态的apache就是类似这样的进程池架构的程序。





