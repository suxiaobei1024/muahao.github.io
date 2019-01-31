---
layout: post
title: "Getting start with ksm in kernel (03)"
author: Ahao Mu
excerpt: Getting start with ksm in kernel (03)
tags:
- kernel
- memory
---

# ksm测试
tags:ksm

## 理解
在 [https://www.kernel.org/doc/Documentation/vm/ksm.txt](https://www.kernel.org/doc/ Documentation/vm/ksm.txt)  中：

可以获得 ksm关键统计信息解释： 

```
pages_shared     - how many shared pages are being used
pages_sharing    - how many more sites are sharing them i.e. how much saved
pages_unshared   - how many pages unique but repeatedly checked for merging
```

## 1. ltp测试ksm过程
### 测试工具：ltp
### 测试原理：
启动3个程序child0, child1, child2

child0: allocates 128 MB filled with 'c'

child1: allocates 128 MB filled with 'a'

child2: allocates 128 MB filled with 'a'

开启ksm scan:

1. 128 MB * 3 = 98304 pages  
2. 实际使用: pages_shared = 2 pages;(child0 的c 合并只占用1个page，child1，child2 page合并只占用1个page)
4. 节约空间: pages_sharing = 98302 pages

```
mem.c:266: PASS: pages_shared is 2.
mem.c:266: PASS: pages_sharing is 98302.
mem.c:266: PASS: pages_volatile is 0.
mem.c:266: PASS: pages_unshared is 0.
mem.c:266: PASS: sleep_millisecs is 0.
mem.c:266: PASS: pages_to_scan is 98304.
```


### 测试结果:

sys cpu 占用：

![image.png](http://ata2-img.cn-hangzhou.img-pub.aliyun-inc.com/25a7f3c5f903f3f1d59eabbaf92b83e8.png)

![image.png](http://ata2-img.cn-hangzhou.img-pub.aliyun-inc.com/1a820f925f0f6e3c0e9af576d528477c.png)




工具测试结果:

```
[root@jiangyi02.sqa.zmf /home/ahao.mah/ltp/testcases/kernel/mem/ksm]
#./ksm03
tst_test.c:908: INFO: Timeout per run is 0h 05m 00s
mem.c:437: INFO: wait for all children to stop.
mem.c:403: INFO: child 0 stops.
mem.c:403: INFO: child 1 stops.
mem.c:403: INFO: child 2 stops.
mem.c:510: INFO: KSM merging...
mem.c:449: INFO: resume all children.
mem.c:359: INFO: child 0 continues...
mem.c:359: INFO: child 1 continues...
mem.c:363: INFO: child 0 allocates 128 MB filled with 'c'
mem.c:359: INFO: child 2 continues...
mem.c:363: INFO: child 1 allocates 128 MB filled with 'a'
mem.c:363: INFO: child 2 allocates 128 MB filled with 'a'
mem.c:415: INFO: child 1 stops.
mem.c:415: INFO: child 0 stops.
mem.c:415: INFO: child 2 stops.
mem.c:299: INFO: ksm daemon takes 20s to scan all mergeable pages
mem.c:309: INFO: check!
mem.c:266: PASS: run is 1.
mem.c:266: PASS: pages_shared is 2.
mem.c:266: PASS: pages_sharing is 98302.
mem.c:266: PASS: pages_volatile is 0.
mem.c:266: PASS: pages_unshared is 0.
mem.c:266: PASS: sleep_millisecs is 0.
mem.c:266: PASS: pages_to_scan is 98304.
mem.c:437: INFO: wait for all children to stop.
mem.c:449: INFO: resume all children.
mem.c:327: INFO: child 1 verifies memory content.
mem.c:327: INFO: child 0 verifies memory content.
mem.c:327: INFO: child 2 verifies memory content.
mem.c:359: INFO: child 1 continues...
mem.c:363: INFO: child 1 allocates 128 MB filled with 'b'
mem.c:359: INFO: child 0 continues...
mem.c:363: INFO: child 0 allocates 128 MB filled with 'c'
mem.c:359: INFO: child 2 continues...
mem.c:363: INFO: child 2 allocates 128 MB filled with 'a'
mem.c:415: INFO: child 1 stops.
mem.c:415: INFO: child 2 stops.
mem.c:415: INFO: child 0 stops.
mem.c:299: INFO: ksm daemon takes 20s to scan all mergeable pages
mem.c:309: INFO: check!
mem.c:266: PASS: run is 1.
mem.c:266: PASS: pages_shared is 3.
mem.c:266: PASS: pages_sharing is 98301.
mem.c:266: PASS: pages_volatile is 0.
mem.c:266: PASS: pages_unshared is 0.
mem.c:266: PASS: sleep_millisecs is 0.
mem.c:266: PASS: pages_to_scan is 98304.
mem.c:437: INFO: wait for all children to stop.
mem.c:449: INFO: resume all children.
mem.c:327: INFO: child 0 verifies memory content.
mem.c:327: INFO: child 2 verifies memory content.
mem.c:327: INFO: child 1 verifies memory content.
mem.c:359: INFO: child 0 continues...
mem.c:363: INFO: child 0 allocates 128 MB filled with 'd'
mem.c:359: INFO: child 1 continues...
mem.c:363: INFO: child 1 allocates 128 MB filled with 'd'
mem.c:359: INFO: child 2 continues...
mem.c:363: INFO: child 2 allocates 128 MB filled with 'd'
mem.c:415: INFO: child 1 stops.
mem.c:415: INFO: child 0 stops.
mem.c:415: INFO: child 2 stops.
mem.c:299: INFO: ksm daemon takes 20s to scan all mergeable pages
mem.c:309: INFO: check!
mem.c:266: PASS: run is 1.
mem.c:266: PASS: pages_shared is 1.
mem.c:266: PASS: pages_sharing is 98303.
mem.c:266: PASS: pages_volatile is 0.
mem.c:266: PASS: pages_unshared is 0.
mem.c:266: PASS: sleep_millisecs is 0.
mem.c:266: PASS: pages_to_scan is 98304.
mem.c:437: INFO: wait for all children to stop.
mem.c:449: INFO: resume all children.
mem.c:327: INFO: child 0 verifies memory content.
mem.c:327: INFO: child 2 verifies memory content.
mem.c:327: INFO: child 1 verifies memory content.
mem.c:359: INFO: child 2 continues...
mem.c:363: INFO: child 2 allocates 128 MB filled with 'd'
mem.c:359: INFO: child 0 continues...
mem.c:363: INFO: child 0 allocates 128 MB filled with 'd'
mem.c:359: INFO: child 1 continues...
mem.c:368: INFO: child 1 allocates 128 MB filled with 'd' except one page with 'e'
mem.c:415: INFO: child 0 stops.
mem.c:415: INFO: child 1 stops.
mem.c:415: INFO: child 2 stops.
mem.c:299: INFO: ksm daemon takes 20s to scan all mergeable pages
mem.c:309: INFO: check!
mem.c:266: PASS: run is 1.
mem.c:266: PASS: pages_shared is 1.
mem.c:266: PASS: pages_sharing is 98302.
mem.c:266: PASS: pages_volatile is 0.
mem.c:266: PASS: pages_unshared is 1.
mem.c:266: PASS: sleep_millisecs is 0.
mem.c:266: PASS: pages_to_scan is 98304.
mem.c:437: INFO: wait for all children to stop.
mem.c:534: INFO: KSM unmerging...
mem.c:449: INFO: resume all children.
mem.c:327: INFO: child 1 verifies memory content.
mem.c:327: INFO: child 0 verifies memory content.
mem.c:327: INFO: child 2 verifies memory content.
mem.c:327: INFO: child 1 verifies memory content.
mem.c:430: INFO: child 1 finished.
mem.c:430: INFO: child 0 finished.
mem.c:430: INFO: child 2 finished.
mem.c:299: INFO: ksm daemon takes 10s to scan all mergeable pages
mem.c:309: INFO: check!
mem.c:266: PASS: run is 2.
mem.c:266: PASS: pages_shared is 0.
mem.c:266: PASS: pages_sharing is 0.
mem.c:266: PASS: pages_volatile is 0.
mem.c:266: PASS: pages_unshared is 0.
mem.c:266: PASS: sleep_millisecs is 0.
mem.c:266: PASS: pages_to_scan is 98304.
mem.c:540: INFO: stop KSM.
mem.c:299: INFO: ksm daemon takes 10s to scan all mergeable pages
mem.c:309: INFO: check!
mem.c:266: PASS: run is 0.
mem.c:266: PASS: pages_shared is 0.
mem.c:266: PASS: pages_sharing is 0.
mem.c:266: PASS: pages_volatile is 0.
mem.c:266: PASS: pages_unshared is 0.
mem.c:266: PASS: sleep_millisecs is 0.
mem.c:266: PASS: pages_to_scan is 98304.

Summary:
passed   42
failed   0
skipped  0
warnings 0
```




## 2. kvm test ksm
注意：测试过程中将ksmd 关闭，避免对测试产生影响;

测试方法：

1. kvm创建fedora01，然后clone方式，获得clone01,clone02....

没有开启：

```
[root@localhost /home/ahao.mah]
#cat /sys/kernel/mm/ksm/run
0

[root@localhost /home/ahao.mah]
#while [ 1 ]; do cat /sys/kernel/mm/ksm/pages_shared; sleep 1; done
0

0
0
0
0
0
0
```

开启ksm: 

```
[root@localhost /home/ahao.mah]
#cat /sys/kernel/mm/ksm/run
1

[root@localhost /data/kvm]
#virsh list --all
 Id    Name                           State
----------------------------------------------------
 2     fedora01                       paused
 4     clone02                        running
 5     clone01                        running
 
[root@localhost /home/ahao.mah]
#while [ 1 ]; do cat /sys/kernel/mm/ksm/pages_shared; sleep 1; done
0
0
0
0
0
147
1200
2320
2453
3101
3970
5231
6407
7727
9342
11058
12999
14803
16764
19085
21169
22987

[root@localhost /home/ahao.mah]
#while [ 1 ]; do cat /sys/kernel/mm/ksm/pages_sharing; sleep 1; done
273202
276604
```



