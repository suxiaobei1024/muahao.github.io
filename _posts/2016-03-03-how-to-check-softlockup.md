---
layout: post
title: "What is softlockup and hardlockup in kernel?"
author: muahao
tags:
- debug
---

# 内核如何检测SOFT LOCKUP与HARD LOCKUP？


所谓lockup，是指某段内核代码占着CPU不放。Lockup严重的情况下会导致整个系统失去响应。Lockup有几个特点：

1. 首先只有内核代码才能引起lockup，因为用户代码是可以被抢占的，不可能形成lockup；

2. 其次内核代码必须处于禁止内核抢占的状态(preemption disabled)，因为Linux是可抢占式的内核，只在某些特定的代码区才禁止抢占，在这些代码区才有可能形成lockup。

### Lockup分为两种：soft lockup 和 hard lockup，它们的区别是 hard lockup 发生在CPU屏蔽中断的情况下。

1. Soft lockup是指CPU被内核代码占据，以至于无法执行其它进程。检测soft lockup的原理是给每个CPU分配一个定时执行的内核线程[watchdog/x]，如果该线程在设定的期限内没有得到执行的话就意味着发生了soft lockup。

2. Hard lockup比soft lockup更加严重，CPU不仅无法执行其它进程，而且不再响应中断。检测hard lockup的原理利用了PMU的NMI perf event，因为NMI中断是不可屏蔽的，在CPU不再响应中断的情况下仍然可以得到执行，它再去检查时钟中断的计数器hrtimer_interrupts是否在保持递增，如果停滞就意味着时钟中断未得到响应，也就是发生了hard lockup。

Linux kernel设计了一个检测lockup的机制，称为NMI Watchdog，是利用NMI中断实现的，用NMI是因为lockup有可能发生在中断被屏蔽的状态下，这时唯一能把CPU抢下来的方法就是通过NMI，因为NMI中断是不可屏蔽的。NMI Watchdog 中包含 soft lockup detector 和 hard lockup detector，2.6之后的内核的实现方法如下。

### NMI Watchdog 的触发机制包括两部分：

一个高精度计时器(hrtimer)，对应的中断处理例程是`kernel/watchdog.c`: `watchdog_timer_fn()`，在该例程中：
要递增计数器`hrtimer_interrupts`，这个计数器供hard lockup detector用于判断CPU是否响应中断；

还要唤醒[watchdog/x]内核线程，该线程的任务是更新一个时间戳；
soft lock detector检查时间戳，如果超过soft lockup threshold一直未更新，说明[watchdog/x]未得到运行机会，意味着
CPU被霸占，也就是发生了soft lockup。

基于PMU的NMI perf event，当PMU的计数器溢出时会触发NMI中断，对应的中断处理例程是 `kernel/watchdog.c`: `watchdog_overflow_callback()`，hard lockup detector就在其中，它会检查上述hrtimer的中断次数(hrtimer_interrupts)是否在保持递增，如果停滞则表明hrtimer中断未得到响应，也就是发生了hard lockup。


### hrtimer的周期是：`softlockup_thresh/5`。

注：

#### 在2.6内核中：

`softlockup_thresh`的值等于内核参数`kernel.watchdog_thresh`，默认60秒；

#### 而到3.10内核中：

内核参数`kernel.watchdog_thresh`名称未变，但含义变成了hard lockup threshold，默认10秒；
soft lockup threshold则等于`（2*kernel.watchdog_thresh）`，即默认20秒。

NMI perf event是基于PMU的，触发周期（hard lockup threshold）在2.6内核里是固定的60秒，不可手工调整；在3.10内核里可以手工调整，因为直接对应着内核参数`kernel.watchdog_thresh`，默认值10秒。

#### 检测到 lockup 之后怎么办？可以自动panic，也可输出条信息就算完了，这是可以通过内核参数来定义的：

1. `kernel.softlockup_panic`: 决定了检测到soft lockup时是否自动panic，缺省值是0；

2. `kernel.nmi_watchdog`: 定义是否开启nmi watchdog、以及hard lockup是否导致panic，该内核参数的格式是”=[panic,][nopanic,][num]”.

（注：最新的kernel引入了新的内核参数`kernel.hardlockup_panic`，可以通过检查是否存在 `/proc/sys/kernel/hardlockup_panic`来判断你的内核是否支持。）

#### 参考资料：
Softlockup detector and hardlockup detector (aka nmi_watchdog)
