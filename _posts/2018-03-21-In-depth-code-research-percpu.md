---
layout: post
title: "In-depth code research - per-cpu-variable"
author: Ahao Mu
excerpt: In-depth code research - per-cpu-variable
tags:
- kernel
---

# per-cpu-variable

多核情况下，CPU是同时并发运行的，但是多它们共同使用其他的硬件资源的，因此我们需要解决多个CPU之间的同步问题。per-cpu-variable（per-cpu-variable）是内核中一种重要的同步机制。顾名思义，per-cpu-variable就是为每个CPU构造一个变量的副本，这样多个CPU相互操作各自的副本，互不干涉。比如我们标识当前进程的变量`current_task`就被声明为per-cpu-variable。

### per-cpu-variable的特点：
* 用于多个CPU之间的同步，如果是单核结构，per-cpu-variable没有任何用处。
* per-cpu-variable不能用于多个CPU相互协作的场景。（每个CPU的副本都是独立的）
* per-cpu-variable不能解决由中断或延迟函数导致的同步问题
* 访问per-cpu-variable的时候，一定要确保关闭进程抢占，否则一个进程被抢占后可能会更换CPU运行，这会导致per-cpu-variable的引用错误。

### 我们可以用数组来实现per-cpu-variable吗？
比如，我们要保护变量var，我们可以声明`int var[NR_CPUS]`，CPU num就访问var[num]不就可以了吗？

显然，per-cpu-variable的实现不会这么简单。理由：我们知道为了加快内存访问，处理器中设计了硬件高速缓存（也就是CPU的cache），每个处理器都会有一个硬件高速缓存。如果per-cpu-variable用数组来实现，那么任何一个CPU修改了其中的内容，都会导致其他CPU的高速缓存中对应的块失效。而频繁的失效会导致性能急剧的下降。

per-cpu-variable分为静态和动态两种: 

* 静态的per-cpu-variable使用`DEFINE_PER_CPU`声明，在编译的时候分配空间；
* 而动态的使用`alloc_percpu`和`free_percpu`来分配回收存储空间。下面我们来看看Linux中的具体实现：

## per-cpu-variable的函数和宏
per-cpu-variable的定义在`./include/linux/percpu-defs.h`以及`./include/linux/percpu.h`中。这些文件中定义了单核和多核情况下的per-cpu-variable的操作，这是为了代码的统一设计的，实际上只有在多核情况下(定义了CONFIG_SMP)per-cpu-variable才有意义。常见的操作和含义如下：

```
DECLARE_PER_CPU(type, name): 声明per-cpu-variablename，类型为type
DEFINE_PER_CPU(type, name): 定义per-cpu-variablename，类型为type
alloc_percpu(type): 动态为type类型的per-cpu-variable分配空间，并返回它的地址
free_percpu(pointer): 释放为动态分配的per-cpu-variable的空间，pointer是起始地址
per_cpu(var, cpu): 获取编号cpu的处理器上面的变量var的副本
get_cpu_var(var): 获取本处理器上面的变量var的副本，该函数关闭进程抢占，主要由__get_cpu_var: 来完成具体的访问
get_cpu_ptr(var): 获取本处理器上面的变量var的副本的指针，该函数关闭进程抢占，主要由__get_cpu_var来完成具体的访问
put_cpu_var(var) & put_cpu_ptr(var): 表示per-cpu-variable的访问结束，恢复进程抢占
__get_cpu_var(var): 获取本处理器上面的变量var的副本，该函数不关闭进程抢占
```

## per-cpu-variable的实现原理
### 静态的per-cpu-variable
通常情况下，静态声明的per-cpu-variable都会被编译在ELF文件中的以`.data.percpu`开头的段中（默认情况就是`.data.percpu`，也可以使用`DEFINE_PER_CPU_SECTION(type, name, sec)`来指定段的后缀, 具体的代码如下：

```
#define DEFINE_PER_CPU(type, name)                  \  
    DEFINE_PER_CPU_SECTION(type, name, "")  
```

```
#define DEFINE_PER_CPU_SECTION(type, name, sec)             \  
    __PCPU_ATTRS(sec) PER_CPU_DEF_ATTRIBUTES            \  
    __typeof__(type) name  
```

```
#define __PCPU_ATTRS(sec)                       \  
    __percpu __attribute__((section(PER_CPU_BASE_SECTION sec))) \  
    PER_CPU_ATTRIBUTES  
```


```
#define PER_CPU_BASE_SECTION ".data..percpu"  
```


```
__attribute__((section(PER_CPU_BASE_SECTION sec)  
```

备注：per-cpu-variable的声明和普通变量的声明一样，主要的区别是使用了`__attribute__((section(PER_CPU_BASE_SECTION sec)))`来指定该变量被放置的段中，普通变量默认会被放置data段或者bss段中。

看到这里有一个问题：如果我们只是声明了一个变量，那么如果有多个副本的呢？奥妙在于内核加载的过程。

一般情况下，ELF文件中的每一个段在内存中只会有一个副本，而.data.percpu段再加载后，又被复制了NR_CPUS次，一个per-cpu-variable的多个副本在内存中是不会相邻。示意图如下：

具体的代码参加`start_kernel`中调用的`setup_per_cpu_areas`函数。代码如下：

```
void __init setup_per_cpu_areas(void)  
{  
    unsigned long delta;  
    unsigned int cpu;  
    int rc;  
  
    /* 
     * Always reserve area for module percpu variables.  That's 
     * what the legacy allocator did. 
     */  
    rc = pcpu_embed_first_chunk(PERCPU_MODULE_RESERVE,  
                    PERCPU_DYNAMIC_RESERVE, PAGE_SIZE, NULL,  
                    pcpu_dfl_fc_alloc, pcpu_dfl_fc_free);  
    if (rc < 0)  
        panic("Failed to initialize percpu areas.");  
  
    delta = (unsigned long)pcpu_base_addr - (unsigned long)__per_cpu_start;  
    for_each_possible_cpu(cpu)  
        __per_cpu_offset[cpu] = delta + pcpu_unit_offsets[cpu];  
}  
```

备注：分配内存以及复制`.data.percup`内容的工作由`pcpu_embed_first_chunk`来完成，这里就不展开了。`__per_cpu_offset`数组中记录了每个CPU的percpu区域的开始地址。我们访问per-cpu-variable就要依靠`__per_cpu_offset`中的地址。

##  动态per-cpu-variable
了解了静态的per-cpu-variable的实现机制后，就很容易想到动态的per-cpu-variable的实现方法了。实际上，在`setup_per_cpu_areas`的时候，我们会为每个CPU都多申请一部分空间留作动态分配per-cpu-variable之用（一个场景就是内核模块中的per-cpu-variable）。相对于静态的per-cpu-variable，我们需要额外管理内存的分配和回收。

### per-cpu-variable的访问
我们以per_cpu为例，来看一下per-cpu-variable的访问是如何实现的。代码如下：

```
#define per_cpu(var, cpu) \  
    (*SHIFT_PERCPU_PTR(&(var), per_cpu_offset(cpu)))  
```
其中`per_cpu_offset`是获取编号为cpu的处理器上的每CPU区域的地址，实际上就是数组`__per_cpu_offset`中对应的项。具体实现如下：

```
#define per_cpu_offset(x) (__per_cpu_offset[x])  
```


```
#define SHIFT_PERCPU_PTR(__p, __offset) ({              \  
    __verify_pcpu_ptr((__p));                   \  
    RELOC_HIDE((typeof(*(__p)) __kernel __force *)(__p), (__offset)); \  
})  
```

```
#define __verify_pcpu_ptr(ptr)  do {                    \  
    const void __percpu *__vpp_verify = (typeof(ptr))NULL;      \  
    (void)__vpp_verify;                     \  
} while (0)  
```

```
# define RELOC_HIDE(ptr, off)                   \  
  ({ unsigned long __ptr;                   \  
     __ptr = (unsigned long) (ptr);             \  
    (typeof(ptr)) (__ptr + (off)); })  
```

备注：`__verify_pcpu`是为了验证var是否是一个per-cpu-variable（如果不是，会再编译的时候报错）。实际上的存取简化后相当于`*(var的地址（即相对偏移）+__per_cpu_offset)`。
