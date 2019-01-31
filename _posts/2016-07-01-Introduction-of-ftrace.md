---
layout: post
title: "Introduction of ftrace"
author: Ahao Mu
tags:
- tracing
---

## ftrace 
https://www.ibm.com/developerworks/cn/linux/l-cn-ftrace1/

https://www.ibm.com/developerworks/cn/linux/l-cn-ftrace/

### 让内核.config支持ftrace的几个tracer：

```
CONFIG_FUNCTION_TRACER 
CONFIG_FUNCTION_GRAPH_TRACER 
CONFIG_CONTEXT_SWITCH_TRACER 
CONFIG_NOP_TRACER 
CONFIG_SCHED_TRACER 
...
```

### 挂载：
ftrace是通过proc来管理，控制tracer的

```
#mount -t debugfs nodev /debug
```

### 当前已经编译进内核的tracer(跟踪器)

```
#cat available_tracers
blk function_graph wakeup_dl wakeup_rt wakeup function nop
```

### 当前tracer

```
#cat /debug/tracing/current_tracer
nop
```

### 开启某个tracer:

```
#echo function_graph > /debug/tracing/current_tracer
```

### 查看trace结果：

```
#cat /debug/tracing/trace
# tracer: function_graph
#
# CPU  DURATION                  FUNCTION CALLS
# |     |   |                     |   |   |   |
  24)   0.600 us    |          } /* vfs_getattr_nosec */
  24)   1.262 us    |        } /* vfs_getattr */
  24)               |        path_put() {
  24)               |          dput() {
  24)   0.034 us    |            _cond_resched();
  24)   0.355 us    |          }

```

### ftrace 的数据文件
/sys/kernel/debug/trace 目录下文件和目录比较多，有些是各种跟踪器共享使用的，有些是特定于某个跟踪器使用的。在操作这些数据文件时，通常使用 echo 命令来修改其值，也可以在程序中通过文件读写相关的函数来操作这些文件的值。下面只对部分文件进行描述，读者可以参考内核源码包中 Documentation/trace 目录下的文档以及 kernel/trace 下的源文件以了解其余文件的用途。

* README文件提供了一个简短的使用说明，展示了 ftrace 的操作命令序列。可以通过 cat 命令查看该文件以了解概要的操作流程。
* current_tracer用于设置或显示当前使用的跟踪器；使用 echo 将跟踪器名字写入该文件可以切换到不同的跟踪器。系统启动后，其缺省值为 nop ，即不做任何跟踪操作。在执行完一段跟踪任务后，可以通过向该文件写入 nop 来重置跟踪器。
* available_tracers记录了当前编译进内核的跟踪器的列表，可以通过 cat 查看其内容；其包含的跟踪器与图 3 中所激活的选项是对应的。写 current_tracer 文件时用到的跟踪器名字必须在该文件列出的跟踪器名字列表中。
* trace文件提供了查看获取到的跟踪信息的接口。可以通过 cat 等命令查看该文件以查看跟踪到的内核活动记录，也可以将其内容保存为记录文件以备后续查看。
* tracing_enabled用于控制 current_tracer 中的跟踪器是否可以跟踪内核函数的调用情况。写入 0 会关闭跟踪活动，写入 1 则激活跟踪功能；其缺省值为 1 。
* set_graph_function设置要清晰显示调用关系的函数，显示的信息结构类似于 C 语言代码，这样在分析内核运作流程时会更加直观一些。在使用 function_graph 跟踪器时使用；缺省为对所有函数都生成调用关系序列，可以通过写该文件来指定需要特别关注的函数。
* buffer_size_kb用于设置单个 CPU 所使用的跟踪缓存的大小。跟踪器会将跟踪到的信息写入缓存，每个 CPU 的跟踪缓存是一样大的。跟踪缓存实现为环形缓冲区的形式，如果跟踪到的信息太多，则旧的信息会被新的跟踪信息覆盖掉。注意，要更改该文件的值需要先将 current_tracer 设置为 nop 才可以。
* tracing_on用于控制跟踪的暂停。有时候在观察到某些事件时想暂时关闭跟踪，可以将 0 写入该文件以停止跟踪，这样跟踪缓冲区中比较新的部分是与所关注的事件相关的；写入 1 可以继续跟踪。
* available_filter_functions记录了当前可以跟踪的内核函数。对于不在该文件中列出的函数，无法跟踪其活动。
* set_ftrace_filter和 set_ftrace_notrace在编译内核时配置了动态 ftrace （选中 CONFIG_DYNAMIC_FTRACE 选项）后使用。前者用于显示指定要跟踪的函数，后者则作用相反，用于指定不跟踪的函数。如果一个函数名同时出现在这两个文件中，则这个函数的执行状况不会被跟踪。这些文件还支持简单形式的含有通配符的表达式，这样可以用一个表达式一次指定多个目标函数；具体使用在后续文章中会有描述。注意，要写入这两个文件的函数名必须可以在文件 available_filter_functions 中看到。缺省为可以跟踪所有内核函数，文件 set_ftrace_notrace 的值则为空。

### ftrace 跟踪器
ftrace 当前包含多个跟踪器，用于跟踪不同类型的信息，比如进程调度、中断关闭等。可以查看文件 available_tracers 获取内核当前支持的跟踪器列表。在编译内核时，也可以看到内核支持的跟踪器对应的选项。

* nop跟踪器不会跟踪任何内核活动，将 nop 写入 current_tracer 文件可以删除之前所使用的跟踪器，并清空之前收集到的跟踪信息，即刷新 trace 文件。
* function跟踪器可以跟踪内核函数的执行情况；可以通过文件 set_ftrace_filter 显示指定要跟踪的函数。
* function_graph跟踪器可以显示类似 C 源码的函数调用关系图，这样查看起来比较直观一些；可以通过文件 set_grapch_function 显示指定要生成调用流程图的函数。
* sched_switch跟踪器可以对内核中的进程调度活动进行跟踪。
* irqsoff跟踪器和 preemptoff跟踪器分别跟踪关闭中断的代码和禁止进程抢占的代码，并记录关闭的最大时长，preemptirqsoff跟踪器则可以看做它们的组合。
* ftrace 还支持其它一些跟踪器，比如 initcall、ksym_tracer、mmiotrace、sysprof 等。ftrace 框架支持扩展添加新的跟踪器。读者可以参考内核源码包中 Documentation/trace 目录下的文档以及 kernel/trace 下的源文件，以了解其它跟踪器的用途和如何添加新的跟踪器。
