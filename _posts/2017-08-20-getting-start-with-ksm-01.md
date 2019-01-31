---
layout: post
title: "Getting start with ksm in kernel (01)"
author: Ahao Mu
tags:
- kernel
- memory
---

## what is kernel ksm?
KERNEL SAME-PAGE MERGING (KSM)

kernel支持： Linux kernel in 2.6.32开始

rhel6.7: 默认关闭

源码：mm/ksm.c 

编译条件：

```
#cat /boot/config-3.10.0-327.ali2010.rc6.alios7.x86_64 | grep CONFIG_KSM=y
CONFIG_KSM=y
```

summary:

1. KSM was originally developed for use with KVM (where it was known as
Kernel Shared Memory)
2. KSM only merges anonymous (private) pages, never pagecache (file) pages.
3. KSM only operates on those areas of address space which an application
has advised to be likely candidates for merging, by using the madvise(2)
system call: int madvise(addr, length, MADV_MERGEABLE).
4. 系统调用：madvise(addr, length, MADV_MERGEABLE)
5. 系统调用：madvise(addr, length, MADV_UNMERGEABLE)， Note: this unmerging call may suddenly require
more memory than is available - possibly failing with EAGAIN, but more
probably arousing the Out-Of-Memory killer.

### 机制
ksm只能对 app指定的使用 `madvise(addr, length, MADV_MERGEABLE)` 的内存地址空间有效，如果app对一段地址空间使用了 `int madvise(addr, length, MADV_UNMERGEABLE)`  那么ksm即使开启，对这块内存是无效的



### ksm用途
Kernel same-page Merging (KSM), used by the KVM hypervisor, allows KVM guests to share identical memory pages. These shared pages are usually common libraries or other identical, high-use data. KSM allows for greater guest density of identical or similar guest operating systems by avoiding memory duplication.

The concept of shared memory is common in modern operating systems. For example, when a program is first started, it shares all of its memory with the parent program. When either the child or parent program tries to modify this memory, the kernel allocates a new memory region, copies the original contents and allows the program to modify this new region. This is known as copy on write.


### KSM的使用方式
#### 使用方式1：/sys 接口

```
开启：
#echo 1 >/sys/kernel/mm/ksm/run

两种关闭方式：0和2 
1. 如下关闭ksm，和systemctl stop ksmtuned  效果一样，ksmctl.c  也是echo 0 关闭的
#echo 0 >/sys/kernel/mm/ksm/run 

2. 当关闭ksm后， any memory pages that were shared prior to deactivating KSM are still shared. To delete all of the PageKSM in the system, use the following command:
#echo 2 >/sys/kernel/mm/ksm/run

```
#### 使用方式2：qemu-kvm提供了systemd service 管理方式
```
#rpm -ql qemu-kvm-common-1.5.3-105.1.alios7.x86_64|  grep ksm
/etc/ksmtuned.conf
/etc/sysconfig/ksm
/usr/lib/systemd/system/ksm.service
/usr/lib/systemd/system/ksmtuned.service
/usr/libexec/ksmctl
/usr/sbin/ksmtuned
```
具体实现：ksmctl.c 实现原理也是echo xx > /sys/kernel/mm/ksm/run

### systemd管理方式管理ksm
#### 1.The KSM Service
* When the ksm service is not started, Kernel same-page merging (KSM) shares only 2000 pages. This default value provides limited memory-saving benefits.
* When the ksm service is started, KSM will share up to half of the host system's main memory. Start the ksm service to enable KSM to share more memory.

```
#systemctl start ksm
```
#### 2.The KSM Tuning Service
1. The ksmtuned service fine-tunes the kernel same-page merging (KSM) configuration by looping and adjusting ksm. 
2. In addition, the ksmtuned service is notified by libvirt when a guest virtual machine is created or destroyed. The ksmtuned service has no options.

```
#systemctl start  ksmtuned
```

#### 3.ksm && ksmtuned
Red Hat Enterprise Linux uses two separate methods for controlling KSM:

1. The ksm service starts and stops the KSM kernel thread.
2. The ksmtuned service controls and tunes the ksm service, dynamically managing same-page merging. ksmtuned starts the ksm service and stops the ksm service if memory sharing is not necessary. When new guests are created or destroyed, ksmtuned must be instructed with the retune parameter to run.

#### 4.ksmtuned 的配置`/etc/ksmtuned.conf`

这里最重要的配置是: npages 的值等价于 `/sys/kernel/mm/ksm/pages_to_scan file.`

#### 5.KSM监控数据`/sys/kernel/mm/ksm/`
ksm的monitoring data,update by kernel , accurate record of KSM usage and statistics.
如下配置 和/etc/ksmtuned.conf  数据是一致的

```
#ll /sys/kernel/mm/ksm/
total 0
-rw-r--r-- 1 root root 4096 Aug  2 20:34 always
-r--r--r-- 1 root root 4096 Aug  2 20:34 full_scans
-rw-r--r-- 1 root root 4096 Aug  2 20:34 merge_across_nodes
-r--r--r-- 1 root root 4096 Aug  2 20:34 pages_shared
-r--r--r-- 1 root root 4096 Aug  2 20:34 pages_sharing
-rw-r--r-- 1 root root 4096 Aug  2 20:34 pages_to_scan
-r--r--r-- 1 root root 4096 Aug  2 20:34 pages_unshared
-r--r--r-- 1 root root 4096 Aug  2 20:34 pages_volatile
-rw-r--r-- 1 root root 4096 Aug  2 20:34 run
-rw-r--r-- 1 root root 4096 Aug  2 20:34 sleep_millisecs

⁠full_scans: Full scans run.
⁠merge_across_nodes: Whether pages from different NUMA nodes can be merged.
⁠pages_shared: Total pages shared.
⁠pages_sharing: Pages currently shared.
⁠pages_to_scan: Pages not scanned.
⁠pages_unshared: Pages no longer shared.
⁠pages_volatile: Number of volatile pages.
⁠run: Whether the KSM process is running.
⁠sleep_millisecs: Sleep milliseconds.

```

```
run              - set 0 to stop ksmd from running but keep merged pages,
                   set 1 to run ksmd e.g. "echo 1 > /sys/kernel/mm/ksm/run",
                   set 2 to stop ksmd and unmerge all pages currently merged,
                         but leave mergeable areas registered for next run
                   Default: 0 (must be changed to 1 to activate KSM,
                               except if CONFIG_SYSFS is disabled)
```

These variables can be manually tuned using the virsh node-memory-tune command. For example, the following specifies the number of pages to scan before the shared memory service goes to sleep:

```
# virsh node-memory-tune --shm-pages-to-scan number

```
#### 6.关闭KSM
ksm有一定的性能开销，所以，ksm一般都是关闭的

永久关闭ksm

```
# systemctl stop ksmtuned
Stopping ksmtuned:                                         [  OK  ]
# systemctl stop ksm
Stopping ksm:                                              [  OK  ]
```

```
# systemctl disable ksm
# systemctl disable ksmtuned
```


## REF

[https://lwn.net/Articles/306704/](https://lwn.net/Articles/306704/)

[https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Virtualization_Tuning_and_Optimization_Guide/chap-KSM.html](https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Virtualization_Tuning_and_Optimization_Guide/chap-KSM.html)

[https://www.kernel.org/doc/Documentation/vm/ksm.txt](https://www.kernel.org/doc/Documentation/vm/ksm.txt)
