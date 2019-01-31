---
layout: post
title: "Tracing - tracepoint in kernel"
author: muahao
excerpt: Tracing - tracepoint in kernel
tags:
- tracing
---

# Linux内核tracepoints
## 简单介绍
内核中的每个tracepoint提供一个钩子来调用probe函数。

一个tracepoint可以打开或关闭。打开时，probe函数关联到tracepoint；

关闭时，probe函数不关联到tracepoint。

tracepoint关闭时对kernel产生的影响很小，只是增加了极少的时间开销（一个分支条件判断），极小的空间开销（一条函数调用语句和几个数据结构）。当一个tracepoint打开时，用户提供的probe函数在每次这个tracepoint执行是都会被调用。


如果用户准备为kernel加入新的tracepoint，每个tracepoint必须以下列格式声明：

```
    #include <linux/tracepoint.h>

    DECLARE_TRACE(tracepoint_name,
                 TPPROTO(trace_function_prototype),
		 TPARGS(trace_function_args));
```

上面的宏定义了一个新的tracepoint叫tracepoint_name。与这个tracepoint关联的probe函数必须与TPPROTO宏定义的函数prototype一致，probe函数的参数列表必须与TPARGS宏定义的一致。

或许用一个例子来解释会比较容易理解。Kernel里面已经包含了一些tracepoints，其中一个叫做sched_wakeup，这个tracepoint在每次scheduler唤醒一个进程时都会被调用。它是这样定义的：

```
    DECLARE_TRACE(sched_wakeup,
	         TPPROTO(struct rq *rq, struct task_struct *p),
		 TPARGS(rq, p))
```

实际在kernel中插入这个tracepoint点的是一行如下代码：

```
    trace_sched_wakeup(rq, p);
```

注意，插入tracepoint的函数名就是将`trace_`前缀添加到`tracepoint_name`的前面。除非有一个实际的probe函数关联到这个tracepoint，`trace_sched_wakeup()`这个只是一个空函数。下面的操作就是将一个probe函数关联到一个tracepoint：

```
    void my_sched_wakeup_tracer(struct rq *rq, struct task_struct *p);

    register_trace_sched_wakeup(my_sched_wakeup_tracer);

```
`register_trace_sched_wakeup()`函数实际上是`DEFINE_TRACE()`定义的，它把probe函数`my_sched_wakeup_tracer()`和`tracepoint sched_wakeup`关联起来。
