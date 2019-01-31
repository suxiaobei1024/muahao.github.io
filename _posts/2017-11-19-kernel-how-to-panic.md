---
layout: post
title: "如何手动触发物理机panic，并产生vmcore?"
author: muahao
excerpt: 如何手动触发物理机panic，并产生vmcore?
tags:
- debug

---

# 如何手动触发物理机panic，并产生vmcore?
## 1. 配置kdump
### 1.1 el6

如果是CentOS 6 则编辑/boot/grub/grub.conf配置在内核参数中添加 crashkernel=auto 类似如下

```
kernel /vmlinuz-2.6.32-xxx.el6.x86_64 ro root=LABEL=/ crashkernel=auto ...
```

### 1.2 el7
如果是CentOS 7 则编辑`/etc/default/grub`修改`GRUB_CMDLINE_LINUX`行添加` crashkernel=auto `类似如下

```
GRUB_CMDLINE_LINUX="crashkernel=auto ..."
```

#### 1.3 只要修改`/etc/default/grub`修改`GRUB_CMDLINE_LINUX`行 ,就需要重新生成grub配置：

```
grub2-mkconfig -o /boot/grub2/grub.cfg
```

如果你遇到服务器极不稳定，需要在系统hung住时候立即crash掉系统生成kernel core dump，则需要使用NMI watchdog，则需要在内核参数中再加上 `nmi_watchdog=1 `激活watchdog（这样就不需要时时盯着服务器来手工触发core）

重启服务器使得以上配置生效

## 2. kdump涉及的sysctl 配置

查阅了网上很多有关kdump的资料，发现在配置kdump时，对sysctl.conf 内的一些配置也进行了调整。这里也列举下，可以根据具体的情况酌情进行修改。

如下参数也都可以在`/etc/default/grub`修改`GRUB_CMDLINE_LINUX`行添加

```
kernel.sysrq=1
kernel.unknown_nmi_panic=1
kernel.softlockup_panic=1
```

### 2.1 sysrq
`kernel.sysrq=1`，如果通过/proc文件配置 ，上面的配置等价于`echo 1 > /proc/sys/kernel/sysrq` . 


默认SysRQ(/proc/sys/kernel/sysrq)设置值是16. 修改这个值为1激活SysRq来触发core dump

```
echo 1 > /proc/sys/kernel/sysrq
echo c > /proc/sysrq-trigger

```
此时在带外可以看到

```
[1290981.013642] SysRq : Trigger a crash
[1290981.018405] BUG: unable to handle kernel NULL pointer dereference at           (null)
[1290981.028007] IP: [<ffffffff813ed756>] sysrq_handle_crash+0x16/0x20
```

然后切换到kdump内核并进行 vmcore 存储

```
         Starting Kdump Vmcore Save Service...
[    7.200189] BTRFS info (device sda4): disk space caching is enabled

kdump: saving to /kdumproot/data//127.0.0.1-2017-01-18-23:33:42/
kdump: saving vmcore-dmesg.txt
kdump: saving vmcore-dmesg.txt complete
kdump: saving vmcore
Copying data                       : [100.0 %] \
kdump: saving vmcore complete
```

打开sysrq键的功能以后，有终端访问权限的用户将会拥有一些特别的功能。如果系统出现挂起的情况或在诊断一些和内核相关，
使用这些组合键能即时打印出内核的信息。

因此，除非是要调试，解决问题，一般情况下，不要打开此功能。如果一定要打开，请确保你的终端访问的安全性。

### 2.2 `kernel.unknown_nmi_panic`
`kernel.unknown_nmi_panic=1` ,如果系统已经是处在Hang的状态的话，那么可以使用NMI按钮来触发Kdump。

开启这个选项可以：`echo 1 > /proc/sys/kernel/unknown_nmi_panic` 需要注意的是，启用这个特性的话，是不能够同时启用`NMI_WATCHDOG`的！否则系统会Panic！




### 2.3 `kernel.softlockup_panic`
`kernel.softlockup_panic=1`,其对应的是`/proc/sys/kernel/softlockup_panic`的值，值为1可以让内核在死锁或者死循环的时候可以宕机重启。如果你的机器中安装了kdump，在重启之后，你会得到一份内核的core文件，这时从core文件中查找问题就方便很多了，而且再也不用手动重启机器了。如果你的内核是标准内核的话，可以通过修改`/proc/sys/kernel/softlockup_thresh`来修改超时的阈值，如果是CentOS内核的话，对应的文件是`/proc/sys/kernel/watchdog_thresh`。


### 2.4 nmi watchdog
#### 2.4.1 编译支持
在很多x86/x86-64类型的硬件中提供了一个功能可以激活watchdog NMI interrupts（NMI：不可屏蔽中断在系统非常困难时依然可以执行）。这个功能可以用来debug内核异常。通过周期性执行MNI中断，内核可以见识任何CPU思索并且打印出相应的debug信息。


为了使用NMI watchdog，你需要在内核激活APIC支持。对于SMP内核，APIC支持已经自动编译进内核。即在内核配置中：

```
CONFIG_X86_UP_APIC (Processor type and features -> Local APIC support on uniprocessors) 

```

或

```
CONFIG_X86_UP_IOAPIC (Processor type and features -> IO-APIC support on uniprocessors) 

```

#### 2.4.2 开启
在 x86 平台，nmi_watchdog默认是关闭的，你需要在启动参数中激活它。

动态修改：

也可以通过对`/proc/sys/kernel/nmi_watchdog`写入0来在运行时关闭NMI watchdog。而写入1这个文件则可以重新激活NMI watchdog。

永久修改：

需要在启动时使用`nmi_watchdog=X`参数来激活NMI watchdog，否则无法动态修改。


```
#grep NMI /proc/interrupts
 NMI:          2          1          0          5          1          0          1          1          0          1          2          0          0         12          1          1          0          0          0          5          1          1          0          0   Non-maskable interrupts
```

#### 2.4.3 nmi watchdog触发kernel crash
当系统挂起并且通常中断都被禁止的故障时，可以通过不可屏蔽中断（non maskable interrupt, NMI）来触发一个panic以及获得crash dump。有两种方式来触发一个NMI，不过这两个方法不能同时使用。





## 3. 手动触发有两个方法：
### 3.1 方法1：使用/proc/sysrq-trigger

```
echo 1 | sudo tee /proc/sys/kernel/sysrq
echo c | sudo tee /proc/sysrq-trigger
```
### 3.2 方法2: 开启nmi
假如，希望机器A 接受nmi后panic

登录A： 

```
echo 1 | sudo tee /proc/sys/kernel/unkown_nmi_panic
```

A的oob IP： 100.126.xx.xx

登录A的机房所在的oob跳板机：

接下来就可以通过网络使用IPMI远程发送`unknown_nmi_panic`信号给服务器触发kernel core dump

```
[root@oob1.xxx /root]
#ipmitool -I lanplus -U name -P xxxxx -H 100.126.xx.xx chassis power diag
Chassis Power Control: Diag
```


```
rt2m09613 login: 
[  287.765130] Kernel panic - not syncing: An NMI occurred. Depending on your system the reason for the NMI is logged in any one of the following resources:
[  287.765130] 1. Integrated Management Log (IML)
[  287.765130] 2. OA Syslog
[  287.765130] 3. OA Forward Progress Log
[  287.765130] 4. iLO Event Log
[  287.926060] CPU: 0 PID: 0 Comm: swapper/0 Tainted: G           OE  ------------   3.10.0-327.xxxxx.x86_64 #1
[  287.990149] Hardware name: HP ProLiant DL380e Gen8, BIOS P73 08/20/2012
[  288.029748]  ffffffffa049e4b0 2df877b6d8f92a53 ffff88183f405de0 ffffffff81631816
[  288.074609]  ffff88183f405e60 ffffffff8162b0ef 0000000000000008 ffff88183f405e70
[  288.118449]  ffff88183f405e10 2df877b6d8f92a53 0000000000000000 ffffc9000c0d2072
[  288.162844] Call Trace:
[  288.177585]  <NMI>  [<ffffffff81631816>] dump_stack+0x19/0x1b
[  288.212435]  [<ffffffff8162b0ef>] panic+0xd8/0x1e7
[  288.240375]  [<ffffffffa049d8ed>] hpwdt_pretimeout+0xdd/0xe0 [hpwdt]
[  288.279340]  [<ffffffff8163a9f9>] nmi_handle.isra.0+0x69/0xb0
[  288.314476]  [<ffffffff8163ab66>] do_nmi+0x126/0x340
[  288.341792]  [<ffffffff81639e31>] end_repeat_nmi+0x1e/0x2e
[  288.374724]  [<ffffffff81058e96>] ? native_safe_halt+0x6/0x10
[  288.409004]  [<ffffffff81058e96>] ? native_safe_halt+0x6/0x10
[  288.442540]  [<ffffffff81058e96>] ? native_safe_halt+0x6/0x10
[  288.476401]  <<EOE>>  [<ffffffff8101dd5f>] default_idle+0x1f/0xc0
[  288.510993]  [<ffffffff8101e666>] arch_cpu_idle+0x26/0x30
[  288.541880]  [<ffffffff810d3185>] cpu_startup_entry+0x245/0x290
[  288.577386]  [<ffffffff81621587>] rest_init+0x77/0x80
[  288.607035]  [<ffffffff81a89057>] start_kernel+0x429/0x44a
[  288.640036]  [<ffffffff81a88a37>] ? repair_env_string+0x5c/0x5c
[  288.675191]  [<ffffffff81a88120>] ? early_idt_handlers+0x120/0x120
[  288.713429]  [<ffffffff81a885ee>] x86_64_start_reservations+0x2a/0x2c
[  288.753833]  [<ffffffff81a88742>] x86_64_start_kernel+0x152/0x175
[    0.000000] Initializing cgroup subsys cpuset
[    0.000000] Initializing cgroup subsys cpu
```


## 4. crash进行结果分析

crash包需要`yum -y install crash` 单独安装过，另外crash 命令需要依赖`kernel-debuginfo `包（该包又依赖`kernel-debuginfo-common`包），该包的下载地址：`http://debuginfo.centos.org/6/x86_64/ `。

下载前先要确认下自己主机的内核版本。我在测试机上是通过下面的命令执行的：

### el6 
```
# uname -r
2.6.32-431.17.1.el6.x86_64
# wget http://debuginfo.centos.org/6/x86_64/kernel-debuginfo-common-x86_64-2.6.32-431.17.1.el6.x86_64.rpm
# wget http://debuginfo.centos.org/6/x86_64/kernel-debuginfo-2.6.32-431.17.1.el6.x86_64.rpm
```

### el7 
```
http://debuginfo.centos.org/7/x86_64/
```


### crash分析案例1 
下载完成后，通过rpm -ivh将这两个包安装。然后通过下面的命令进行crash分析

```
# pwd
/var/crash/127.0.0.1-2014-09-16-14:35:49
# crash /usr/lib/debug/lib/modules 2.6.32-431.17.1.el6.x86_64/vmlinux vmcore
crash 6.1.0-5.el6
Copyright (C) 2002-2012  Red Hat, Inc.
Copyright (C) 2004, 2005, 2006, 2010  IBM Corporation
Copyright (C) 1999-2006  Hewlett-Packard Co
Copyright (C) 2005, 2006, 2011, 2012  Fujitsu Limited
Copyright (C) 2006, 2007  VA Linux Systems Japan K.K.
Copyright (C) 2005, 2011  NEC Corporation
Copyright (C) 1999, 2002, 2007  Silicon Graphics, Inc.
Copyright (C) 1999, 2000, 2001, 2002  Mission Critical Linux, Inc.
This program is free software, covered by the GNU General Public License,
and you are welcome to change it and/or distribute copies of it under
certain conditions.  Enter "help copying" to see the conditions.
This program has absolutely no warranty.  Enter "help warranty" for details.
GNU gdb (GDB) 7.3.1
Copyright (C) 2011 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.  Type "show copying"
and "show warranty" for details.
This GDB was configured as "x86_64-unknown-linux-gnu"...
      KERNEL: /usr/lib/debug/lib/modules/2.6.32-431.17.1.el6.x86_64/vmlinux
    DUMPFILE: vmcore  [PARTIAL DUMP]
        CPUS: 1
        DATE: Tue Sep 16 22:35:49 2014
      UPTIME: 00:05:33
LOAD AVERAGE: 0.00, 0.00, 0.00
       TASKS: 175
    NODENAME: localhost.localdomain
     RELEASE: 2.6.32-431.17.1.el6.x86_64
     VERSION: #1 SMP Wed May 7 23:32:49 UTC 2014
     MACHINE: x86_64  (3398 Mhz)
      MEMORY: 1 GB
       PANIC: "Oops: 0002 [#1] SMP " (check log for details)
         PID: 1412
     COMMAND: "bash"
        TASK: ffff88003d0b2040  [THREAD_INFO: ffff88003c33c000]
         CPU: 0
       STATE: TASK_RUNNING (PANIC)
crash> bt
PID: 1412   TASK: ffff88003d0b2040  CPU: 0   COMMAND: "bash"
 #0 [ffff88003c33d9e0] machine_kexec at ffffffff81038f3b
 #1 [ffff88003c33da40] crash_kexec at ffffffff810c59f2
 #2 [ffff88003c33db10] oops_end at ffffffff8152b7f0
 #3 [ffff88003c33db40] no_context at ffffffff8104a00b
 #4 [ffff88003c33db90] __bad_area_nosemaphore at ffffffff8104a295
 #5 [ffff88003c33dbe0] bad_area at ffffffff8104a3be
 #6 [ffff88003c33dc10] __do_page_fault at ffffffff8104ab6f
 #7 [ffff88003c33dd30] do_page_fault at ffffffff8152d73e
 #8 [ffff88003c33dd60] page_fault at ffffffff8152aaf5
    [exception RIP: sysrq_handle_crash+22]
    RIP: ffffffff8134b516  RSP: ffff88003c33de18  RFLAGS: 00010096
    RAX: 0000000000000010  RBX: 0000000000000063  RCX: 0000000000000000
    RDX: 0000000000000000  RSI: 0000000000000000  RDI: 0000000000000063
    RBP: ffff88003c33de18   R8: 0000000000000000   R9: ffffffff81645da0
    R10: 0000000000000001  R11: 0000000000000000  R12: 0000000000000000
    R13: ffffffff81b01a40  R14: 0000000000000286  R15: 0000000000000004
    ORIG_RAX: ffffffffffffffff  CS: 0010  SS: 0018
 #9 [ffff88003c33de20] __handle_sysrq at ffffffff8134b7d2
#10 [ffff88003c33de70] write_sysrq_trigger at ffffffff8134b88e
#11 [ffff88003c33dea0] proc_reg_write at ffffffff811f2f1e
#12 [ffff88003c33def0] vfs_write at ffffffff81188c38
#13 [ffff88003c33df30] sys_write at ffffffff81189531
#14 [ffff88003c33df80] system_call_fastpath at ffffffff8100b072
    RIP: 00000036e3adb7a0  RSP: 00007fff22936c10  RFLAGS: 00010206
    RAX: 0000000000000001  RBX: ffffffff8100b072  RCX: 0000000000000400
    RDX: 0000000000000002  RSI: 00007fab7908b000  RDI: 0000000000000001
    RBP: 00007fab7908b000   R8: 000000000000000a   R9: 00007fab79084700
    R10: 00000000ffffffff  R11: 0000000000000246  R12: 0000000000000002
    R13: 00000036e3d8e780  R14: 0000000000000002  R15: 00000036e3d8e780
    ORIG_RAX: 0000000000000001  CS: 0033  SS: 002b
crash> 
```


上面，只是简单的通过打印堆栈信息，显示主机在出现kdump生成时，pid 为1412的bash进程操作。从上面的显示信息中也简单的看到有 `write_sysrq_trigger` 函数触发。crash在定位问题原因时，为我们提供了下面的命令：


```
crash> ?
*              files          mach           repeat         timer
alias          foreach        mod            runq           tree
ascii          fuser          mount          search         union
bt             gdb            net            set            vm
btop           help           p              sig            vtop
dev            ipcs           ps             struct         waitq
dis            irq            pte            swap           whatis
eval           kmem           ptob           sym            wr
exit           list           ptov           sys            q
extend         log            rd             task
crash version: 6.1.0-5.el6   gdb version: 7.3.1
For help on any command above, enter "help <command>".
For help on input options, enter "help input".
For help on output options, enter "help output".
```

### crash分析案例2 
```
2017-04-08 03:34:51    [29201245.714153] io-error-guard: catch 1 continuous bio error.
2017-04-08 03:34:51    [29201245.722046] Buffer I/O error on device sdc, logical block 0
...
2017-04-08 03:34:51    [29201245.781675] BUG: unable to handle kernel NULL pointer dereference at 0000000000000008
2017-04-08 03:34:51    [29201245.790380] IP: [] netoops+0x125/0x2a0
2017-04-08 03:34:51    [29201245.796262] PGD 371206d067 PUD 1c17f34067 PMD 0 
2017-04-08 03:34:51    [29201245.801494] Oops: 0000 [#1] SMP 
...
2017-04-08 03:34:51    [29201245.941654] Pid: 21606, comm: sh Tainted: GF          ---------------    2.6.32-358.23.2.ali1233.el5.x86_64 #1 Inspur SA5212M4/YZMB-00370-109
2017-04-08 03:34:51    [29201245.955245] RIP: 0010:[]  [] netoops+0x125/0x2a0
...
2017-04-08 03:34:51    [29201246.085431] Call Trace:
2017-04-08 03:34:51    [29201246.088422]   
2017-04-08 03:34:51    [29201246.091092]  [] kmsg_dump+0x113/0x180
2017-04-08 03:34:51    [29201246.096875]  [] bio_endio+0x12a/0x1b0
2017-04-08 03:34:51    [29201246.102652]  [] req_bio_endio+0x90/0xc0
2017-04-08 03:34:51    [29201246.108601]  [] blk_update_request+0x262/0x480
2017-04-08 03:34:51    [29201246.115165]  [] blk_update_bidi_request+0x27/0x80
2017-04-08 03:34:51    [29201246.121984]  [] blk_end_bidi_request+0x2f/0x80
2017-04-08 03:34:51    [29201246.128542]  [] blk_end_request+0x10/0x20
2017-04-08 03:34:51    [29201246.134665]  [] blk_end_request_err+0x33/0x60
2017-04-08 03:34:51    [29201246.141140]  [] scsi_io_completion+0x2db/0x5b0
2017-04-08 03:34:51    [29201246.147699]  [] scsi_finish_command+0xc3/0x120
2017-04-08 03:34:51    [29201246.154258]  [] scsi_softirq_done+0x101/0x170
2017-04-08 03:34:51    [29201246.160734]  [] blk_done_softirq+0x83/0xa0
2017-04-08 03:34:51    [29201246.166944]  [] __do_softirq+0xbf/0x220
2017-04-08 03:34:51    [29201246.172895]  [] call_softirq+0x1c/0x30
2017-04-08 03:34:51    [29201246.178757]  [] do_softirq+0x65/0xa0
2017-04-08 03:34:51    [29201246.184451]  [] irq_exit+0x7c/0x90
2017-04-08 03:34:51    [29201246.189968]  [] smp_call_function_single_interrupt+0x34/0x40
2017-04-08 03:34:51    [29201246.198017]  [] call_function_single_interrupt+0x13/0x20
2017-04-08 03:34:51    [29201246.205438]   
2017-04-08 03:34:51    [29201246.208106]  [] ? wait_for_rqlock+0x24/0x40
2017-04-08 03:34:51    [29201246.214403]  [] do_exit+0x5e6/0x8d0
2017-04-08 03:34:51    [29201246.220003]  [] do_group_exit+0x41/0xb0
2017-04-08 03:34:51    [29201246.225957]  [] sys_exit_group+0x17/0x20
2017-04-08 03:34:51    [29201246.231996]  [] system_call_fastpath+0x16/0x1b
```

找到对应的vmcore

```
cd tmp/linux-2.6.32-358.23.2.el5

gdb vmlinux

//转换Oops中的Call Trace中函数源代码位置

(gdb) l *bio_endio+0x12a

/// 就可以定位到出现故障时候源代码的位置

0xffffffff811b292a is in bio_endio (fs/bio.c:1474).
1469                }
1470            }
1471        }
1472        spin_unlock(&eio->lock);
1473        if (sysctl_enable_bio_netoops)
1474            kmsg_dump(KMSG_DUMP_SOFT, NULL);
1475    }
1476
1477    /**
1478     * bio_endio - end I/O on a bio
(gdb)
注意
```



### REF
[我需要内核的源代码](https://wiki.centos.org/zh/HowTos/I_need_the_Kernel_Source)
