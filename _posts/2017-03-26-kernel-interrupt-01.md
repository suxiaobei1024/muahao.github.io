---
layout: post
title: "kernel interrupt - softirq, tasklet, workqueue"
author: muahao
tags:
- kernel
---

# Interrupt and interrupt handler
## Interrupt
### Interrupt handler
interrupt handler is called by kernel to handle interrupt, and at this interrupt context, the interrupt handler can not be preemptive. 

### Top half and bottom half

## Interrupt handler register 
```
<linux/interrupt.h>

int request_irq(unsigned int irq, 
					irq_handler_t handler, 
					unsigned long flags, 
					const char *name, 
					void *dev);

irq -> iterrupt number
handler-> the pointer of the interrupt's handler function
flags -> handler flag
```

### A interrupt handler example
```
request_irq();

if (request_irq(irqn, my_interrupt, IRQF_SHARED, "my_device", my_dev)) {
	printk(KERN_ERR "my_device: cannot register IRQ %d\n", irqn);
	return -EIO;
}
```

### Release interrupt handler
When uninstall driver, 	should unregister the interrupt handler function. 

```
void free_irq(unsigned int irq, void *dev);
```

The summary is these two function: 

```
request_irq();
free_irq();
```
## How to write a interrupt handler function?
eg: ./arch/x86/kernel/rtc.c

drivers/char/rtc.c

```
#vim drivers/char/rtc.c
if (request_irq(rtc_irq, rtc_interrupt, IRQF_SHARED, "rtc", (void *)&rtc_port)) {
	rtc_has_irq = 0;
	printk(KERN_ERR "rtc: cannot register IRQ %d\n", rtc_irq);
	return -EIO;
}

中断号: rtc_irq
interrupt handler: rtc_interrupt
```

```
static irqreturn_t rtc_interrupt(int irq, void *dev_id)
{
    /*
     *  Can be an alarm interrupt, update complete interrupt,
     *  or a periodic interrupt. We store the status in the
     *  low byte and the number of interrupts received since
     *  the last read in the remainder of rtc_irq_data.
     */

    spin_lock(&rtc_lock);
    rtc_irq_data += 0x100;
    rtc_irq_data &= ~0xff;
    if (is_hpet_enabled()) {
        /*
         * In this case it is HPET RTC interrupt handler
         * calling us, with the interrupt information
         * passed as arg1, instead of irq.
         */
        rtc_irq_data |= (unsigned long)irq & 0xF0;
    } else {
        rtc_irq_data |= (CMOS_READ(RTC_INTR_FLAGS) & 0xF0);
    }

    if (rtc_status & RTC_TIMER_ON)
        mod_timer(&rtc_irq_timer, jiffies + HZ/rtc_freq + 2*HZ/100);

    spin_unlock(&rtc_lock);
	...
	...
```
## Interrupt context

## /proc/interrupts


## Interrupt control
### 禁止和激活中断
禁止当前处理器的本地中断


```
local_irq_disable();
local_irq_enable();
```

如果在`local_irq_disable()`之前 已经执行了 `local_irq_disable()`，那是很危险的. 同样在执行`local_irq_enable()` 之前已经执行了`local_irq_enable()` 也是很危险的. 这两个函数都是无条件的去执行，这很危险，我们不希望这样，我们只是希望有一种机制，可以把中断恢复到之前的状态, 所以，内核提供了新的方法： 

```
unsigned long flags

local_irq_save(flags);
...
local_irq_restore(flags);

1. Bellow two function must be called in the same function
```

### 禁止指定中断线 
前面内容所讲的是， 禁止整个处理器上的所有中断的函数，其实，某些时候，我们只是想禁止整个系统下的一个特定的中短线就够了！也就是所谓的屏蔽掉一条中短线.

```
void disable_irq(unsigned int irq);
void disable_irq_nosync(unsigned int irq);
void enable_irq(unsigned int irq);
void synchronize_irq(unsigned int irq);
```

### 中断系统的状态



## 下半部
1. 中断分为上半部，和下半部， 中断处理程序是在上半部，那么，上半部执行哪些工作？ 下半部执行哪些工作？ 整个没有明确的规定，但是原则，就是，上半部要执行尽量少的工作，越快越好，因为，中断发生的时候，可能是打断了别的进程，所以上半部一定要快，要快，不能有睡眠，等，的现象!
3. 如果当前中断处理程序中，有`IRQF_DISABLE`被设置了， 那么当前处理器上的其他所有中断都会被屏蔽，这是一个比较坏的情况。
4. 上半部一般只会执行一些简单的操作，比如，对影响置位，告诉硬件，我收到了你的中断，其他的工作都会扔给下半部，比如，响应网卡，上半部会响应网卡我执行收到了你的中断，也有可能在这个时候会将网卡队列中的数据copy到内存中，下半部的工作，就是要处理这些包，**下半部的关键在于当他们运行的时候，允许响应所有的中断**， 那么下半部一般什么执行呢？ 一般上半部执行完之后，下半部就会执行。


为什么会有下半部？ 

因为，在中断处理中，总有一些工作要推迟去做，我们把这种推迟机制，称之为 “下半部机制”。 
这种机制的实现方式有好几种, 


### softirq
#### 软中断的定义
其实是用一个struct定义，当前，一共有32个softirq， 放在一个数组`softirq_vec `中: 

```
struct softirq_action {
	void (*action) (struct softirq_action *);
}

```
```
static struct softirq_action softirq_vec[NR_SOFTIRQS];
```


#### 软中断处理程序
软中断处理程序action函数原型

```
void softirq_handler(struct softirq_action *);
```
when kernel run a softirq handler process, it will excute this `action` function. 

```
my_softirq->action(my_softirq)
```
一个软中断，不会抢占另外一个软中断， 只有中断处理程序，才可以抢占软中断

#### 执行软中断 
什么时候执行软中断？ 一个注册的软中断，只有在被标记之后，才会被执行，这我们称之为 触发软中断(raising the softirq), 通常，中断处理程序，会在返回前标记它的软中断，使其在稍后会被执行，在合适的时刻，该软中断就会被执行，在下面地方，软中断会被检查和执行： 

1. 在ksoftirq内核线程中
2. 从一个硬件中断代码返回时

无论使用什么办法，最后都会调用 `do_softirq()`中执行. 这个函数很简单，如果 有需要处理的软中断，`do_softirq()` 会循环遍历每一个，调用它们的处理程序。

```
asmlinkage __visible void do_softirq(void)
{
    __u32 pending;
    unsigned long flags;

    if (in_interrupt())
        return;

    local_irq_save(flags);

    pending = local_softirq_pending(); 

    if (pending && !ksoftirqd_running())
        do_softirq_own_stack();

    local_irq_restore(flags);
}

```

1. 局部变量pending保存， `local_softirq_pending`宏的返回值. 它是待处理的软中断的32位的位图。如果第n位设置为1 ， 表示第n位对应的类型的软中断等待处理。


### 使用软中断
现在定义软中断是在./include/linux/interrupt.h 下， 利用一个enum，软中断是有编号的，这个编号代表了优先级，编号越小，越先被执行。

分配索引


```
enum
{
    HI_SOFTIRQ=0, //优先级高的tasklet
    TIMER_SOFTIRQ, //定时器的下半部
    NET_TX_SOFTIRQ,	//发送网络软件包
    NET_RX_SOFTIRQ, //接受网络软件包
    BLOCK_SOFTIRQ,
    IRQ_POLL_SOFTIRQ,
    TASKLET_SOFTIRQ,
    SCHED_SOFTIRQ,
    HRTIMER_SOFTIRQ, /* Unused, but kept as tools rely on the
                numbering. Sigh! */
    RCU_SOFTIRQ,    /* Preferable RCU should always be the last softirq */

    NR_SOFTIRQS
};
```
#### 注册你的软中断处理程序
通过调用`open_softirq` 注册软中断处理程序，此函数有两个参数， 软中断索引号， 软中断处理函数

比如： 网络处理包的软中断处理函数注册方法： 

```
net/core/dev.c: open_softirq(NET_TX_SOFTIRQ, net_tx_action);
net/core/dev.c: open_softirq(NET_RX_SOFTIRQ, net_rx_action);
```

#### 触发你的软中断
当我们在enum枚举中新增了一个软中断索引，然后通过`open_softirq`进行注册之后，新的软中断处理程序就会投入运行，`raise_softirq()` 函数会将一个软中断设置为挂起状态，然后下次调用`do_softirq()`（可能是ksoftirq）的时候，就会运行：

举例： 

```
raise_softirq(NET_TX_SOTFIRQ);
```

Well, then the softirq handler `net_tx_action()` will be called soon.

**在中断处理程序中 调用 软中断，是非常常见的， 这种情况下，中断处理程序执行硬件设备相关的操作，然后触发软中断，最后 中断处理程序 退出， 然后马上执行 `do_softirq()`函数，中断中的 “上半部” 和 “下半部” 就是这么分工的**


### tasklet
tasklet是利用软中断实现一种下半部机制。

什么时候使用tasklet， 大部分时候使用tasklet， 很少直接使用softirq.

tasklet有两类软中断代表: 

```
HI_SOFTIRQ
TASKLET_SOFTIRQ
```

两者区别在于，前者优先于后者执行。

#### tasklet实现
tasklet 有 `tasklet_struct` 结构表示，每个结构体单独代表一个tasklet，

```
vim <linux/interrupt.h>

struct tasklet_struct {
	struct tasklet_struct *next;
	unsigned long state;
	atomic_t count;
	void (*func)(unsigned long);
	unsigned long data;
}
```

* func代表tasklet处理程序；
* data是func的唯一的参数
* state成员只能在0， `TASKLET_STATE_SCHED`, `TASKLET_STATE_RUN`之间取值,`TASKLET_STATE_SCHED`, 表示tasklet已经被调度，`TASKLET_STATE_RUN`表示正在运行。
* count是tasklet的引用计数，非0表示tasklet被禁止，只有为0表示tasklet被激活。

##### 对于这个结构的初始化

```
void tasklet_init(struct tasklet_struct *t,
          void (*func)(unsigned long), unsigned long data)
{
    t->next = NULL;
    t->state = 0;
    atomic_set(&t->count, 0);
    t->func = func;
    t->data = data;
}
```

举例，初始化一个tasklet，那么tasklet 处理函数可能就是 `__tasklet_hrtimer_trampoline `

```
void tasklet_hrtimer_init(struct tasklet_hrtimer *ttimer,
              enum hrtimer_restart (*function)(struct hrtimer *),
              clockid_t which_clock, enum hrtimer_mode mode)
{
    hrtimer_init(&ttimer->timer, which_clock, mode);
    ttimer->timer.function = __hrtimer_tasklet_trampoline;
    tasklet_init(&ttimer->tasklet, __tasklet_hrtimer_trampoline,
             (unsigned long)ttimer);
    ttimer->function = function;
}
```
#### 调度tasklet
`tasklet_vec`, `tasklet_hi_vec`都是由`struct tasklet_struct`组成的链表，但是`tasklet_hi_vec`优先级更高，链表中的每一个元素`struct tasklet_struct`都代表一个不同的tasklet。

tasklet是由`tasklet_schedule()` 和 `tasklet_hi_schedule`函数进行调度的，他们接受一个指向`tasklet_struct` 结构的指针作为参数。却别在于，分别使用了`TASKLET_SOFTIRQ`, `HI_SOFTIRQ`.

#### tasklet_schedule实现

```
static inline void tasklet_schedule(struct tasklet_struct *t)
{
    if (!test_and_set_bit(TASKLET_STATE_SCHED, &t->state))
        __tasklet_schedule(t);
}

void __tasklet_schedule(struct tasklet_struct *t)
{
    unsigned long flags;

    local_irq_save(flags);
    t->next = NULL;
    *__this_cpu_read(tasklet_vec.tail) = t;
    __this_cpu_write(tasklet_vec.tail, &(t->next));
    raise_softirq_irqoff(TASKLET_SOFTIRQ);
    local_irq_restore(flags);
}
```
执行步骤： 

1. 检查tasklet状态s会否是`TASKLET_STATE_SCHED`,如果是，说明tasklet已经被调度了，函数立刻返回。
2. 调用 `__tasklet_schedule`
3. 保存中断状态，然后禁止本地中断
4. 把需要调度的tasklet加到每个处理器上的一个`tasklet_vec` list or `tasklet_hi_vec` list head
5. **唤起`TASKLET_SOFTIRQ()`, OR `TASKLET_HI_SOFTIRQ`，这样下次，调用到`do_softirq()`就会执行到这个tasklet.**
6. 恢复中断到原来状态，返回 


`do_softirq()`会尽可能早的在下一个时机去执行，但是由于大部分tasklet和软中断都是在中断处理程序中被设置成了待处理状态，所以，最近一次中断返回的时候，就是执行 `do_softirq()`的时机.


#### 使用tasklet
##### 声明自己的tasklet

```
DECLARE_TASKLET(name, func, data);
DECLARE_TASKLET_DISABLED(name, func, data);
```
这两个宏，都是根据给定的名字，静态的创建一个`tasklet_struct`结构。 当这个tasklet被调度之后，给定的func会被执行。它的参数由data给出。

##### 编写自己的tasklet处理程序
##### 调度自己的tasklet
```
tasklet_schedule(&my_tasklet);
```
##### ksoftirq

### 工作队列
#### 工作队列实现
工作队列子系统是一个，用来创建内核线程的接口，通过它创建的进程负责执行由内核其他部分排到队列里的任务。  它创建的内核线程，我们称之为 "worker thread"， 默认的工作线程"events/n". 


表示这个线程的数据结构`workqueue_struct`

```
vim kernel/workqueue.c 

struct workqueue_struct {
	struct cpu_workqueue_struct  cpu_wq[NR_CPUS];
	struct list_head list;
	const char *name;
	int singlethread;
	int freezeable;
	int rt;
}
```

表示工作的数据结构

```
struct work_struct {
    atomic_long_t data;
    struct list_head entry;
    work_func_t func;
#ifdef CONFIG_LOCKDEP
    struct lockdep_map lockdep_map;
#endif
};
```

所有的工作的线程都会调用`worker_thread()`函数。 在它初始化完成以后，这些函数执行一个死循环，并且开始休眠，当有操作被插入到队列的时候，线程就会被再次唤醒。


