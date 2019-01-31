---
layout: post
title: "Getting start with ksm in kernel (02)"
author: Ahao Mu
tags:
- kernel
- memory
---

## 前言
前几天对ksm在虚拟化环境中进行了测试发现效果很不错，由于ksm有一定的性能开销，对其缺点难以评估。所以，需要对ksm从源码上理解其原理，知道ksm可能带来的任何潜在问题，方可能找到可能让生产接受的途径。

本人也是kernel层面的初学者，如果有理解不正的地方还请指点。在ksm源码中大量使用内核双链表和红黑树，初次接触kernel内核源码的同学来说，还是有不小的难度，需要对内核中的list.h 双链表有一定的理解和使用上的感觉，还要rbtree的有一定的理解，不然，基本上看不懂。不过最近几天每次潜心去看都能有了更深的理解。

本次先对ksm源码中最关键核心的函数进行梳理，纪录一下学习过程。

首先，ksm是通过kthread的方式运行的内核线程，ksm永远都是单线程的，其中主要运行函数是：`ksm_do_scan`，然后，我们设置一个值，`scan_npages`，表示每一次 扫描多少个page，扫描完这些pages后，就会休息一会儿，这个值大概是：`ksm_thread_sleep_millisecs`。

ksm中最重要的一个数据结构是`rmap_item`,通过madvise，我们知道了我们要扫描的地址范围，并且保存到`mm_slot`链表中，然后，利用`scan_get_next_rmap_item` 获得每个page的反向映射项`rmap_item `,后续的内存的对比，合并基本通过这个结构体。 

同时，ksm 设计了两个rbtree，一个stable tree，一个unstable tree。 这些tree的node其实是`rmap_tree`组成,每个虚拟地址一一对应一个`rmap_item`.

利用`scan_get_next_rmap_item` 获得每个虚拟地址的`rmap_item`数据结构，然后首先和stable tree对比，如果发现内容一致，则合并，内容不一致，则，计算其checksum和上次对比，如果发现不一致，表明这个page发生了变化，进而和unstable tree对比.如果发现有一样的，则，把两者全部从unstable  tree中转移到stable tree中，如果没有发现一致的，则在unstable tree新增一个新的node.


## 1.`ksm_do_scan`
KSM的初始化函数`ksm_init`负责启动内核进程ksmd，使用语句`kthread_run(ksm_scan_thread, NULL, "ksmd")`，根据函数`ksm_scan_thread`创建了内核守护进程ksmd。

`ksm_scan_thread`扫描线程只要内核线程未被终止就会一直执行`ksm_do_scan`(每个周期要扫描的页数量)，执行完一个周期后，要休眠`ksm_thread_sleep_millisecs`时间，如此反复。

`ksm_do_scan`是ksm主要的功能部分,它实现了:

1. 匿名页及其反向映射项的线性获取——`scan_get_next_rmap_item `, 我们获得每个page对应的reverse mapping item `rmap_item`
2. 然后进行比较和页合并——`cmp_and_merge_page`,函数根据这个page struct和`rmap_item` 首先判断是否可以合并到稳定树中
3. 并且在页不满足共享条件时将页的写保护属性移除——`break_cow`。

```
/**
 * ksm_do_scan  - the ksm scanner main worker function.
 * @scan_npages - number of pages we want to scan before we return.
 */
static void ksm_do_scan(unsigned int scan_npages)
{
    struct rmap_item *rmap_item;
    struct page *uninitialized_var(page);

    while (scan_npages-- && likely(!freezing(current))) { //scan_npages定义每次扫描的page数量
        cond_resched();
        rmap_item = scan_get_next_rmap_item(&page); //获得page结构体物理页对应的rmap_item
        if (!rmap_item)
            return;
        cmp_and_merge_page(page, rmap_item);
        put_page(page);
    }
}
```


## 2.`cmp_and_merge_page`
现介绍`cmp_and_merge_page`函数的主要任务，比较和合并页函数;

1. 首先将待合并的页,与稳定树比较,看页能否合并进稳定树
2. 假如不能在稳定树中找到与待合并页内容一致的页,那么计算页的校验和checksum看看是否等于页原有的oldchecksum值
3. 假如校验和未发生改变意味着页内容在两次扫描过程中未发生变化，页是非易失的，可以将此页继续与非稳定树中的页进行比较看其能否插入到非稳定树中，或者与非稳定树的页一起合并到稳定树中。


```
static void cmp_and_merge_page(struct page *page, struct rmap_item *rmap_item)
{
...
    /* We first start with searching the page inside the stable tree */
    kpage = stable_tree_search(page);   //1
    if (kpage == page && rmap_item->head == stable_node) {  //如果rmap_item 中rmap_item->head == stable_node) ，那么可以说明，这个rmap_item就已经在stable_tree中
        put_page(kpage);
        return;
    }

    remove_rmap_item_from_tree(rmap_item); //2
...
}
```

`remove_rmap_item_from_tree`将`rmap_item`从稳定树或非稳定树中移除？

实际上假如页的反向映射项中能说明页属于稳定树时，可以什么都不做，跳过比较与合并步骤。在此，将其从稳定树中移除，等价于将原先已合并的节点中的页重新释放出来重新进行比较合并，增加了计算开销。

### 2.1 在稳定树中查找 `stable_tree_search` 

```
static struct page *stable_tree_search(struct page *page){
...
...
}
```

接下来继续分析，稳定树中相同页的查找`stable_tree_search`，首先找到稳定树的根节点：
`root_stable_tree.rb_node`，其中

`static struct rb_root root_stable_tree = RB_ROOT;`  //定义了红黑树根结构体类型的变量`root_stable_tree`，并`初始化为(struct rb_root) { NULL, }`  而

```
 struct rb_root
{
         struct rb_node *rb_node;  // rb_root结构体由指向rb_node的指针构成
}

```

也就是说`root_stable_tree`的指向`rb_node`的指针被复制为NULL。NULL指针的类型是`rb_root`结构体类型。

从稳定树的根开始，根据node获取`rmap_item`，调用的是`rb_entry`函数，函数的定义为：

```
#define rb_entry(ptr, type, member) container_of(ptr, type, member)。
```

根据结构体
`rmap_item`中包含的组成单元`rb_node`类型的node得到指向`rmap_item`结构体的指针：

```
struct rmap_item {
    struct list_head link;
    struct mm_struct *mm;
    unsigned long address;      /* + low bits used for flags below */
    union {
        unsigned int oldchecksum;       /* when unstable */
        struct rmap_item *next;         /* when stable */
    };
    union {
        struct rb_node node;            /* when tree node */
        struct rmap_item *prev;         /* in stable list */
    };  
}; 
```
 

若返回`rmap_item`指针不为空，也就是说可以获得反向映射项，那么调用`get_ksm_page`函数检查`rmap_item`所追踪的虚拟地址对应的page是否仍然是`PageKsm`, 假如页保持为`PageKsm`, 则可认为页内容保持不变，并返回获取的页。假如页被震动过则返回NULL。

由于稳定树中的node中得到的`tree_rmap_item`得到的ksm页为NULL，则说明这个反向映射项不再满足合并条件，需要从稳定树中移除，所以有了以下操作：

```
            next_rmap_item = tree_rmap_item->next;      // 首先遍历rmap_item链表
            remove_rmap_item_from_tree(tree_rmap_item);  //移除返回NULL的反向映射项
            tree_rmap_item = next_rmap_item;   //将next_rmap_item复制给下一个要操作的tree_rmap_item
```

操作的原因是由于稳定树的结构决定的：


![](http://images2017.cnblogs.com/blog/970272/201709/970272-20170911120518110-619145320.png)


但是当`tree_rmap_item`得到了节点对应的ksm page则跳过以上3个步骤。将得到的页与待合并的页进行比较：

```
 ret = memcmp_pages(page, page2[0]);
```

根据返回值，决定如何沿着树的左右分支进行继续查找。直至找到相同页，或者遍历完成稳定树。由于同一节点上所有的`rmap_item`都代表同一物理页，所以只要得到有一项得到了一个ksm页，就跳到下一节点，无须获得同一节点`rmap_item`链的下一项。

简单看一下 `memcmp_pages`函数，根据要对比的两个页结构体得到两个地址，然后从地址所指向的位置取`PAGE_SIZE`大小进行比较：
`ret = memcmp(addr1, addr2, PAGE_SIZE);`

以上就是稳定树中查找的基本过程。
### 2.2 稳定树中没有，则计算checksum `calc_checksum ` 

```
    checksum = calc_checksum(page);
    if (rmap_item->oldchecksum != checksum) {
        rmap_item->oldchecksum = checksum;
        return;
    }
```

### 2.3 在不稳定树中查找并插入 `unstable_tree_search_insert` 

`unstable_tree_search_insert`这个函数在非稳定树中为正在扫描的当前页寻找内容等同页，如果没有找到，则在`unstable tree`中插入`rmap_item`作为新的对象。如果找到了，则函数返回相同的`rmap_item`的指针。

__函数返回指向的找到的待扫描页的等同页的`rmap_item`指针，否则返回NULL。__

若`unstable_tree_search_insert`成功找到与扫描页等同页，则将这两项合并到稳定树中

### 2.4 `try_to_merge_two_pages`
`try_to_merge_two_pages`，首先检查稳定树中的节点是否超过了最大可合并页数目。若未超过限制则从内核页池中分配一个页。假如要合并的两页中已经有一个ksm页，则使用`try_to_merge_with_ksm_page`，否则使用`try_to_merge_one_page`。

首先将page1拷贝到新分配的内核页中，然后调用 `try_to_merge_one_page`完成page1与kpage的合并，然后在将page2与kpage合并，从而实现了非稳定树中同内容页与待扫描页page2与page1合并到稳定树中。

其中`try_to_merge_with_ksm_page`与`try_to_merge_two_pages`类似，区别在于不分配新的内核页，最后仍然需要调用`try_to_merge_one_page(vma, page1, kpage)`完成合并。函数定义为：

```
static int try_to_merge_one_page(struct vm_area_struct *vma,
                 struct page *oldpage,
                 struct page *newpage)
```


`cmp_and_merge_page`整个例程结束。
## 3. `ksm_do_scan`的最后
`ksm_do_scan`的最后是将未共享的ksm页用普通页替换。一次扫描在预定义`scan_npages`自减为零时结束。`ksm_scan_thread`的结束需要所有内存建议的mm结构体都被遍历到才结束：

```

static int ksmd_should_run(void)
{
    return (ksm_run & KSM_RUN_MERGE) && !list_empty(&ksm_mm_head.mm_list);
}

```

用户程序通过系统调用函数`madvise`,最终调用`ksm_madvise`函数完成需要共享的`mm_struct`结构体注册为可合并的`VM_MERGEABLE`。`ksm_madvise`又调用
`__ksm_enter(mm)`完成操作。`__ksm_enter(mm)`将`mm_struct`结构体mm插入到扫描游标
`ksm_scan`后方，使得要扫描范围增大。

`list_add_tail(&mm_slot->mm_list, &ksm_scan.mm_slot->mm_list);`


