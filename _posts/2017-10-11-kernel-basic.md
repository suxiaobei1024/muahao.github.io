---
layout: post
title: "Comprehence PTR_ERR,ERR_PTR,IS_ERR"
author: muahao
excerpt: Comprehence PTR_ERR,ERR_PTR,IS_ERR
tags:
- kernel
---

# 解读PTR_ERR,ERR_PTR,IS_ERR

看到了几个宏PTR_ERR,ERR_PTR,IS_ERR（其实是内联函数）.还是不太明白,然后就google搜索了一下，搜出来的结果真是不让人满意，看完一些解释我更迷糊了。看来还得依靠内核源码，依靠对内核的理解自己弄明白了。大致看了一下这几个宏的定义还有在内核的用法，恍然大悟。原来这几个宏这么简单，原理也这么简单。下面就说一下这几个宏的由来与用处。

我们知道内核有些函数是返回指针的，如Kmalloc分配内存，如果分配不到内核就会返回NULL指针，这样我们可以通过判断是否是NULL指针来判断Kmalloc执行成功与否。但是有些函数返回错误时，我们不仅需要知道函数错了，还需要知道错在哪里了，也就是说我们要或得错误码。在用户空间编程的时候，因为每个线程都有一个error变量，我们可以通过访问这个变量来得到错误码。但是在内核就没有这个变量，所以不能这样或得函数执行的错误码。那么聪明的内核开发着就根据内核的地址空间特点用了一种新的方法来或得错误码，那就是PTR_ERR,ERR_PTR,IS_ERR这三个宏，暂时先不说这三个宏怎么用，我们来看一下错误码与内核地址空间的特点。

基本的错误码在内核中的errno－base.h中，如下：

```

#define EPERM        1  /* Operation not permitted */  
#define ENOENT       2  /* No such file or directory */  
#define ESRCH        3  /* No such process */  
#define EINTR        4  /* Interrupted system call */  
#define EIO      5  /* I/O error */  
#define ENXIO        6  /* No such device or address */  
。。。。。。。  
  
#define EFBIG       27  /* File too large */  
#define ENOSPC      28  /* No space left on device */  
#define ESPIPE      29  /* Illegal seek */  
#define EROFS       30  /* Read-only file system */  
#define EMLINK      31  /* Too many links */  
#define EPIPE       32  /* Broken pipe */  
#define EDOM        33  /* Math argument out of domain of func */  
#define ERANGE      34  /* Math result not representable */  
```

在不同的体系结构中也有一些err的宏定义，但是内核规定总的大小不能超过4095.说完了e错误码，然后在说一下内核的地址空间。我们知道Linux是基于虚拟内存的内核，所以CPU访问的是线性地址，而线性地址需要通过页表来转化成物理地址，如若一个线性地址的页表不存在的话会发生缺页异常。Linux在内核地址空间映射了大于0xc0000000的所有可用线性地址，而对于小于0xc0000000的线性地址在内核态是没有页表的，内核也从不使用小于0xc0000000的线性地址。也就是说内核返回指针的函数，如果执行正确，他返回的指针的大小绝对不会小于0xc0000000。如果小于这个那么肯定是错误的。所以可以利用这一点。内核函数都遵守一个约定，那就是如果不能返回正确的指针，那么就返回错误的，我们把返回的错误指针作为错误码。因为错误码都是整数，而返回的是指针，所以需要强制转换一下，这就诞生了这三个宏PTR_ERR,ERR_PTR,IS_ERR。这三个宏（内联函数）的定义在err.h中

```
#define MAX_ERRNO   4095  
  
#ifndef __ASSEMBLY__  
  
#define IS_ERR_VALUE(x) unlikely((x) >= (unsigned long)-MAX_ERRNO)  
  
static inline void *ERR_PTR(long error)  
{  
    return (void *) error;  
}  
  
static inline long PTR_ERR(const void *ptr)  
{  
    return (long) ptr;  
}  
  
static inline long IS_ERR(const void *ptr)  
{  
    return IS_ERR_VALUE((unsigned long)ptr);  
}  
```

判断是否为错误指针也是很简单unlikely((x) >= (unsigned long)-MAX_ERRNO)，这里问什么是大于简单说一下，以为错误码在返回的时候都去负数了，负数大的他的绝对值就小了。就是这个道理。至于这里为什么是4095,那就是内核约定的了，注意这里与什么页面大小没有一点关系，内核完全可以约定0xbfffffff,也是可以的，因为小于0xc0000000的线性地址都是错误的。这三个宏这样用。首先是一个返回指针的内核函数，比如 ：

```
struct device *foo()  
{  
      ...  
      if(...) {//错误了  
              return ERR_PTR(-EIO);  
      }  
}  
```

我们在调用这个函数的时候：

```
struct device ＊d；  
 d ＝ foo（）；  
 if （IS_ERR(d)) {  
       long err = PTR_ERR(d);     
       printk("errno is %d\n", err);  
 } 
``` 

这样就可以提取错误码，然后根据错误码再做什么处理就由具体的驱动来处理了。我感觉其实将内核的机构与原理理解清楚了，内核的一些技巧就非常好理解了。


## TEST 

ERR_PTR : 这里PTR是pointer的意思

PTR_ERR

IS_ERR

```
#cat hello.c
// Defining __KERNEL__ and MODULE allows us to access kernel-level code not usually available to userspace programs.
#undef __KERNEL__
#define __KERNEL__

#undef MODULE
#define MODULE

// Linux Kernel/LKM headers: module.h is needed by all modules and kernel.h is needed for KERN_INFO.
#include <linux/module.h>    // included for all kernel modules
#include <linux/kernel.h>    // included for KERN_INFO
#include <linux/init.h>        // included for __init and __exit macros
#include <linux/err.h>

struct student {
	char *name;
	int age;
};

struct student *func1(void)
{
	if (1) {
		printk(KERN_INFO "call func1()\n");
		return ERR_PTR(-EIO);     // 一般都是func1（）的返回值是指针，这个时候，需要ERR_PTR，将errno转换成pointer
	}
}

static int __init hello_init(void)
{
    printk(KERN_INFO "Hello world!\n");

	struct student *p;

	p = func1();
	if (IS_ERR(p)) {   //IS_ERR()其实是在判断指针
		long err = PTR_ERR(p);         //再将指针转换成long err 
		printk(KERN_INFO "errno is %ld\n", err);
	}

    return 0;    // Non-zero return means that the module couldn't be loaded.
}

static void __exit hello_cleanup(void)
{
    printk(KERN_INFO "Cleaning up module.\n");
}

module_init(hello_init);
module_exit(hello_cleanup);

```

```
#cat Makefile
obj-m := hello.o
KDIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
```

执行make
