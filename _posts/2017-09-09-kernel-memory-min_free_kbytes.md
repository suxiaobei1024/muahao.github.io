---
layout: post
title: "调整内核参数:vm.min_free_kbytes引发的故障"
author: muahao
excerpt: 调整内核参数
tags:
- kernel
- memory
---

### 内核参数：内存相关
内存管理从三个层次管理内存，分别是node, zone ,page;

64位的x86物理机内存从高地址到低地址分为: Normal DMA32 DMA.随着地址降低。

```
[root@localhost01 /home/ahao.mah]
#cat /proc/zoneinfo  |grep "Node"
Node 0, zone      DMA
Node 0, zone    DMA32
Node 0, zone   Normal
Node 1, zone   Normal
```

每个zone都有自己的min low high,如下，但是单位是page

```
[root@localhost01 /home/ahao.mah]
#cat /proc/zoneinfo  |grep "Node 0, zone" -A10
Node 0, zone      DMA
  pages free     3975
        min      20
        low      25
        high     30
        scanned  0
        spanned  4095
        present  3996
        managed  3975
    nr_free_pages 3975
    nr_alloc_batch 5
--
Node 0, zone    DMA32
  pages free     382873
        min      2335
        low      2918
        high     3502
        scanned  0
        spanned  1044480
        present  513024
        managed  450639
    nr_free_pages 382873
    nr_alloc_batch 584
--
Node 0, zone   Normal
  pages free     11105097
        min      61463
        low      76828
        high     92194
        scanned  0
        spanned  12058624
        present  12058624
        managed  11859912
    nr_free_pages 11105097
    nr_alloc_batch 12344
```

```
low = 5/4 * min
high = 3/2 * min

[root@localhost01 /home/ahao.mah]
#T=min;sum=0;for i in `cat /proc/zoneinfo  |grep $T | awk '{print $NF}'`;do sum=`echo "$sum+$i" |bc`;done;sum=`echo "$sum*4/1024" |bc`;echo "sum=${sum} MB"
sum=499 MB

[root@localhost01 /home/ahao.mah]
#T=low;sum=0;for i in `cat /proc/zoneinfo  |grep $T | awk '{print $NF}'`;do sum=`echo "$sum+$i" |bc`;done;sum=`echo "$sum*4/1024" |bc`;echo "sum=${sum} MB"
sum=624 MB

[root@localhost01 /home/ahao.mah]
#T=high;sum=0;for i in `cat /proc/zoneinfo  |grep $T | awk '{print $NF}'`;do sum=`echo "$sum+$i" |bc`;done;sum=`echo "$sum*4/1024" |bc`;echo "sum=${sum} MB"
sum=802 MB
```

### min 和 low的区别：
1. min下的内存是保留给内核使用的；当到达min，会触发内存的direct reclaim
2. low水位比min高一些，当内存可用量小于low的时候，会触发 kswapd回收内存，当kswapd慢慢的将内存 回收到high水位，就开始继续睡眠

### 内存回收方式
内存回收方式有两种，主要对应low ，min

1. direct reclaim :  触发min水位线时执行
2. kswapd reclaim :  触发low水位线时执行


### 在el5下有一个参数: `vm.extra_free_kbytes`

这个参数含义是： `low = min_free_kbytes*5/4 + extra_free_kbytes` . 但是在7u下没有此参数.

```
[root@localhost02 /root]
#sysctl  -a | grep free
vm.min_free_kbytes = 512000
vm.extra_free_kbytes = 512000
```

```
[root@localhost02 /root]
#sysctl  -a | grep free
vm.min_free_kbytes = 512000
vm.extra_free_kbytes = 512000
fs.quota.free_dquots = 0

[root@localhost02 /root]
#T=min;sum=0;for i in `cat /proc/zoneinfo  |grep $T | awk '{print $NF}'`;do sum=`echo "$sum+$i" |bc`;done;sum=`echo "$sum*4/1024" |bc`;echo "sum=${sum} MB"
sum=499 MB

[root@localhost02 /root]
#T=low;sum=0;for i in `cat /proc/zoneinfo  |grep $T | awk '{print $NF}'`;do sum=`echo "$sum+$i" |bc`;done;sum=`echo "$sum*4/1024" |bc`;echo "sum=${sum} MB"
sum=1124 MB

[root@localhost02 /root]
#echo "499*5/4 + (512000/1024)"| bc
1123
```

### 注意
最近有业务线在调大min值得时候导致物理机hang引发故障，得出一些经验和建议：

1. 对于线上128G的内存的机器，可以考虑将min设置为512M左右。因为，太大了，可能会导致内存的浪费；当然如果只有40G的物理机，更不要考虑把min设置超过1G了，这样会导致频繁的触发内存回收；具体优化也要根据业务来看。
2. 关键是在于调整内存的内核参数的时候！ 调大的风险远大于调小的风险！ 如果有人想将`vm.min_free_kbytes` 调大，千万要注意当前的水位，如果一旦调大`vm.min_free_kbytes` 立刻触发direct reclaim，可能会导致机器hang住，ping的通，ssh不上，影响业务！hang住的原因是当`vm.min_free_kbytes` 是512M的时候，此时 free只有1G，此时正常运行，此时如果调大vm.min_free_kbytes 到5G，将会direct reclaim失败。
