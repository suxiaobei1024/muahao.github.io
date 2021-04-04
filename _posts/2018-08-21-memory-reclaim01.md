---
layout: post
title: "内存回收-优化01"
author: muahao
excerpt: 内存回收-优化01
tags:
- memory
---

# 内存回收
## 前言
传统的内存回收的核心在于几个LRU之间的管理，通过min，low，high设定了水位机制，并且设计了kswapd，Direct reclaim两种回收机制；当启动回收动作时，执行shrink函数，开始从LRU上裁剪page;

这种思想很完美，但也有不完美之处。

首先，它总是基于active list和inactive list来判断哪些page可以回收，active和inactive总是一个相对的概念，虽然LRU算法很机智的引入了“双重认证”机制(即使用两个FLAG：`PG_active` 和`PG_referenced`来决定page应该放在LRU的哪个链表之上,从而判断哪些不可以回收), 但是,却缺少一个相对时间的概念。从这个角度上讲，内核的内存回收逻辑，似乎缺少了一定的灵活性。在这里，我们是不是可以通过某种机制，来给每个page赋予“age”（年龄）的概念，这样我们便可以知道，内存所有的page中，有哪些page 24h没有被访问，或者48h没有被访问，并且标记他们，创造一个新的“判断标准”，来决定哪些page应该被回收。最终的目标是：业务方可以根据自己的需求，业务类型，来判断，多少小时没有被访问的page，称之为“冷内存”，然后决定是否，对这些冷内存进行回收？以及何时回收？

如果每个page都有了“age”的概念，我们可以发现，有些很久没有访问的page理应被回收的，但是基于LRU的算法，依然可能还存在于LRU的active list里，也许，我们可以依托这个新的“判断标准”，辅助传统的基于LRU算法的“判断标准”，两者相辅相成，完善内核内存回收逻辑功能；

通过这个新的基于时间的对page的“判断标准”，提供一套API接口给用户态，让用户可以 根据 “时间”这个维度，来提前完成内存的回收，这样，将大大的提高用户管理使用内存的灵活性，大大降低内存回收进入kswapd或者“直接回收”触发的概率，增强稳定性，降低风险；

这里，我们只是新增一个“内存回收”体系，并不是取缔传统的基于LRU算法的内存回收逻辑。本文，主要先介绍传统的内存回收逻辑，然后，因为，为什么需要新引入一种基于时间的“内存回收”机制。

## 内存回收简述
在内核的内存管理中，有几个重要的主线，其中，一个是内存分配，另外一个就是内存回收。

Linux内核的内存回收机制又有这两种主要方式去完成，1. 主动释放，2.linux内核提供的另外一个内存回收机制:PFRA页框回收算法。

内存回收的两种方式：

1. 主动释放；
2. 页框回收算法(PFRA)回收；

主动释放： 用户程序通过free函数释放曾经通过malloc函数分配的内存，页面的使用者明确知道页面什么时候要被使用，什么时候又不再需要了。这就是主动释放，用户从上层调用释放函数free，实际内存释放工作还是需要内核协助完成， 对于直接从伙伴系统分配的页面，这是由使用者使用`free_pages`之类的函数主动释放的，页面释放后被直接放归伙伴系统；从slab中分配的对象（使用`kmem_cache_alloc`函数），也是由使用者主动释放的（使用`kmem_cache_free`函数）。

页框回收算法(PFRA)回收: linux内核 提供的页框回收算法（PFRA）进行回收，页面的使用者一般将页面当作某种缓存，以提高系统的运行效率。缓存一直存在固然好，但是如果缓存没有了也不会造成什么错误，仅仅是效率受影响而已。页面的使用者不明确知道这些缓存页面什么时候最好被保留，什么时候最好被回收，这些都交由PFRA来关心。 简单来说，PFRA要做的事就是回收这些可以被回收的页面。为了避免系统陷入页面紧缺的困境，PFRA会在内核线程中周期性地被调用运行。或者由于系统已经页面紧缺，试图分配页面的内核执行流程因为得不到需要的页面，而同步地调用PFRA。

## PFRA页框回收算法/LRU
对于整个内存回收来说，lru链表是关键中的关键，实际上整个内存回收，做的事情就是处理lru链表的收缩.

### LRU类型
根据page的类型，又分成几种类型的LRU,每个zone中都会保5个LRU链表:

* `LRU_INACTIVE_ANON`：称为非活动匿名页lru链表，此链表中保存的是此zone中所有最近没被访问过的并且可以存放到swap分区的页描述符，在此链表中的页描述符的`PG_active`标志为0。
* `LRU_ACTIVE_ANON`：称为活动匿名页lru链表，此链表中保存的是此zone中所有最近被访问过的并且可以存放到swap分区的页描述符，此链表中的页描述符的`PG_active`标志为1
* `LRU_INACTIVE_FILE`：称为非活动文件页lru链表，此链表中保存的是此zone中所有最近没被访问过的文件页的页描述符，此链表中的页描述符的`PG_active`标志为0。
* `LRU_ACTIVE_FILE`：称为活动文件页lru链表，此链表中保存的是此zone中所有最近被访问过的文件页的页描述符，此链表中的页描述符的`PG_active`标志为1。
* `LRU_UNEVICTABLE`：此链表中保存的是此zone中所有禁止换出的页的描述符。（一般都是mlock函数锁定的page，可能是文件页，也可能是匿名页）

内核定义:

```
enum lru_list {
    LRU_INACTIVE_ANON = LRU_BASE,
    LRU_ACTIVE_ANON = LRU_BASE + LRU_ACTIVE,
    LRU_INACTIVE_FILE = LRU_BASE + LRU_FILE,
    LRU_ACTIVE_FILE = LRU_BASE + LRU_FILE + LRU_ACTIVE,
    LRU_UNEVICTABLE,
    NR_LRU_LISTS
};
```

总之，我们知道，文件页有两个lru俩表（active，inactive），匿名页有两个lru链表（active，inactive），还有一个链表是“unevictable”（mlock指定的page，不希望被参与active，inactive，主观上不希望被回收的）。

### 双重认证-进入active list
如何判断一个page是active还是inactive，内核提供了“双重认证”的思想；也就是说，当一个page被access后，内核不会傻傻的直接将它放入active list中，而是会调用`mark_page_accessed()`函数，使用这个函数来完成一个page的“双重认证”，每个page都有FLAG，这里提供两个FLAG:`PG_active`,`PG_referenced`，如果这个page未曾访问过，先`PG_referenced` 置位，如果，这个page的`PG_referenced`已经置位，`mark_page_accessed()`函数才会对这个page的`PG_active`进行置位；总之，只有当 `PG_active`置位后，这个page，才可以被挂入active list中；

pfra在回收page frame的时候首先是从inactive里开始的。每个page都有两个位来标识page属于的list，以及是否被访问过。它们是`PG_active`和`PG_referenced`.由于这两个位值的不同，page可以分为4种状态:

```
PG_active=0 PG_referenced=0
PG_active=0 PG_referenced=1
PG_active=1 PG_referenced=0
PG_active=1 PG_referenced=1
```

影响这些位的值的有以下函数：

```
mark_page_accessed()
page_referenced()
```

尤其是`mark_page_accessed()`函数,完成了当一个page被访问后，`PG_active`,`PG_referenced` 两个flag之间的转换！

```
/*
 * Mark a page as having seen activity.
 *
 * inactive,unreferenced    ->  inactive,referenced
 * inactive,referenced      ->  active,unreferenced
 * active,unreferenced      ->  active,referenced
 *
 * When a newly allocated page is not yet visible, so safe for non-atomic ops,
 * __SetPageReferenced(page) may be substituted for mark_page_accessed(page).
 */
void mark_page_accessed(struct page *page)
{

}
```

从page的flag中的这两个字段，我们就可以，将page放在不同的LRU中；

### LRU相关函数
一个page是如何加入到某个LRU链表上的，并且如何在在几个LRU链表之间游动的，这涉及到一些相关的函数：

* 新页加入lru链表
    * 当需要将一个新页需要加入到lru链表中，此时必须先加入到当前CPU的`lru_add_pvec`缓存中，一般通过`__lru_cache_add()`函数进行加入
* 将处于非活动链表中的页移动到非活动链表尾部
    * 主要通过`rotate_reclaimable_page()`函数实现，这种操作主要使用在：当一个脏页需要进行回收时，系统首先会将页异步回写到磁盘中(swap分区或者对应的磁盘文件)，然后通过这种操作将页移动到非活动lru链表尾部。这样这些页在下次内存回收时会优先得到回收。
* 将活动lru链表中的页加入到非活动lru链表中
    * 这个操作使用的场景是文件系统主动将一些没有被进程映射的页进行释放时使用，就会将一些活动lru链表的页移动到非活动lru链表中，在内存回收过程中并不会使用这种方式。主要是将活动lru链表中的页加入到`lru_deactivate_pvecs`这个CPU的lru缓存实现，而加入函数，是`deactivate_page()`。
* 将非活动lru链表的页加入到活动lru链表
    * 将活动lru链表的页加入到非活动lru链表中，这种操作主要在一些页是非活动的，之后被标记为活动页了，这时候就需要将这些页加入到活动lru链表中，这个操作一般会调用`activate_page()`实现

## 哪些页应该被回收
### 文件页
文件页都是可以被丢弃并回收的。但是如果页面是脏页面，则丢弃之前必须将其写回磁盘。
### 匿名页
匿名页则都是不可以丢弃的，因为页面里面存有用户程序正在使用的数据，丢弃之后数据就没法还原了。相比之下，文件页本身是保存在磁盘上的，可以复现。于是，要想回收匿名页，只好先把页面上的数据转储到磁盘，这就是页面交换（swap）。显然，页面交换的代价相对更高一些。

匿名页可以被交换到磁盘上的交换文件或交换分区上（分区即是设备，设备即也是文件。所以下文统称为交换文件）。

### 不可回收的
于是，除非页面被保留或被上锁（页面标记`PG_reserved/PG_locked`被置位。某些情况下，内核需要暂时性地将页面保留，避免被回收），所有的磁盘高速缓存页面都可回收，所有的匿名映射页面都可交换。

### PFRA
进行页面回收的时候，PFRA要做两件事情:

1. 将active链表中最近最少使用的页面移动到inactive链表
2. 尝试将inactive链表中最近最少使用的页面回收。

## 何时发生内存回收
### 通过水位:min,low,high 决定何时回收
那么kernel 什么时候认为内存是不够的, 需要做 page reclaim呢?

我们通过 cat /proc/zoneinfo 可以看到这样的信息

```
Node 1, zone   Normal
  pages free     19387934
        min      11289
        low      14111
        high     16933
```

内核提供了一个接口，用户可以通过设置`/proc/sys/vm/min_free_kbytes` 来定义一个水位，min，low，high。

* `wmark_min`: 是说当前的这个空闲的 page frame 已经极低了, 当有内存申请操作的时候, 如果是非内核的内存申请操作, 那么就返回失败, 如果申请操作来自kernel, 比如调用的是 `__alloc_pages_high_priority()` 的时候, 就可以返回内存
* `wmark_low`: 是用来唤醒 kswap 进程, 当我们某一个`__alloc_pages` 的时候发现 free page frame 小于 wmark_low 的时候, 就会唤醒这个kswapd 进程, 进行 page reclaim
* `wmark_high`: 是当 kswapd 这个进程进行 page reclaim 了以后, 什么时候停止的标志, 只有当 page frame 数目大于这个 page_high 的时候, kswapd 进程才会停止, 继续sleep

从上文中，可以看出min的值，决定了low的值，和high的值；从kernel源码中可以知道min low high之间计算关系就是：

```
 watermark[min] = min_free_kbytes换算为page单位即可，假设为min_free_pages。（因为是每个zone各有一套watermark参数，实际计算效果是根据各个zone大小所占内存总大小的比例，而算出来的per zone min_free_pages）
 watermark[low] = watermark[min] * 5 / 4
 watermark[high] = watermark[min] * 3 / 2
```

### 回收方式
通过这3个水位线，内核定义了2种回收方式：

1. kswapd回收
    * 当可用内存少于low的时候，就会启动kswapd线程，根据LRU算法进行内存回收，直到可用内存到达high的时候，停止回收；
2. 直接内存回收（direct page reclaim）
    * 当可用内存少于min的时候，会直接触发“直接回收（direct page reclaim）” ，这个时候内核认为，内存非常紧急了；

`min_free_kbytes`设的越大，watermark的线越高，同时三个水线之间的buffer量也相应会增加。这意味着会较早的启动kswapd进行回收，且会回收上来较多的内存（直至watermark[high]才会停止），这会使得系统预留过多的空闲内存，从而在一定程度上降低了应用程序可使用的内存量。极端情况下设置min_free_kbytes接近内存大小时，留给应用程序的内存就会太少而可能会频繁地导致OOM的发生。

`min_free_kbytes`设的过小，则会导致系统预留内存过小。kswapd回收的过程中也会有少量的内存分配行为（会设上PF_MEMALLOC）标志，这个标志会允许kswapd使用预留内存；另外一种情况是被OOM选中杀死的进程在退出过程中，如果需要申请内存也可以使用预留部分。这两种情况下让他们使用预留内存可以避免系统进入deadlock状态

## 传统内存回收面临的问题
在内核传统的基于LRU算法的内存回收机制之下，并不是完全的完美，从实际生产中，经常会有业务方还是会经常触发到“Direct reclaim”, 毕竟，我们现在已经步入到轻量级，轻应用的容器时代，一个容器的内存可能就只有8G，可能用户的一个malloc步子太大就直接走到了“直接内存回收”逻辑，而且，水位min low high之间的关系，并不一定完美的契合应用的申请内存的行为。我们提供了一组patch，拉大min，low之间的gap，使得，更加容易触发kswapd的回收的概率，来尽量减少触发到“Direct reclaim”触发的概率。 但是，一个基于“时间”（age）的新的内存回收逻辑和体系，如果能够实现，将会大大提高，用户控制内存的灵活性，用户可以在任意的时刻，从时间维度，判断，哪些内存是X小时以上没有使用的page，然后，回收掉。降低稳定性风险，提高成本利用率。

