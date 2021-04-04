---
layout: post
title: "Linux kernel 内存 - 页表映射（SHIFT，SIZE，MASK）和转换(32位，64位)"
author: muahao
excerpt: "Linux kernel 内存 - 页表映射（SHIFT，SIZE，MASK）和转换(32位，64位)"
tags:
- memory
- kernel
---

## 0. Intro
如下是在32位下的情况，32位下，只有三级页表：PGD，PMD，PTE

在64位情况下，会有四级页表：PGD，PUD，PMD，PTE

但是原理基本上是一样的，本文主要是想记录一下页表转换中的几个 基本概念宏：SHITF，SIZE，MASK以及之间的转换。


## 1. Linux虚拟内存三级页表 （本文以32位为主线）
Linux虚拟内存三级管理由以下三级组成：

* PGD: Page Global Directory (页目录)
* PMD: Page Middle Directory (页目录)
* PTE:  Page Table Entry  (页表项)

    
每一级有以下三个关键描述宏：

* SHIFT
* SIZE
* MASK

如页的对应描述为：

```
/* PAGE_SHIFT determines the page size  asm/page.h */
#define PAGE_SHIFT		12
#define PAGE_SIZE		(_AC(1,UL) << PAGE_SHIFT)
#define PAGE_MASK		(~(PAGE_SIZE-1))
```

数据结构定义如下：

```
/* asm/page.h */
typedef unsigned long pteval_t;
 
typedef pteval_t pte_t;
typedef unsigned long pmd_t;
typedef unsigned long pgd_t[2];
typedef unsigned long pgprot_t;
 
#define pte_val(x)      (x)
#define pmd_val(x)      (x)
#define pgd_val(x)	((x)[0])
#define pgprot_val(x)   (x)
 
#define __pte(x)        (x)
#define __pmd(x)        (x)
#define __pgprot(x)     (x)
```


## 2 Page Directory (PGD and PMD)
每个进程有它自己的PGD( Page Global Directory)，它是一个物理页，并包含一个pgd_t数组。其定义见<asm/page.h>。 进程的pgd_t数据见 task_struct -> mm_struct -> pgd_t * pgd;    

ARM架构的PGD和PMD的定义如下<arch/arm/include/asm/pgtable.h>：

```
#define PTRS_PER_PTE  512 // PTE中可包含的指针<u32>数 (21-12=9bit) #define PTRS_PER_PMD  1 #define PTRS_PER_PGD  2048 // PGD中可包含的指针<u32>数 (32-21=11bit)

#define PTE_HWTABLE_PTRS (PTRS_PER_PTE) #define PTE_HWTABLE_OFF  (PTE_HWTABLE_PTRS * sizeof(pte_t)) #define PTE_HWTABLE_SIZE (PTRS_PER_PTE * sizeof(u32))

/*  * PMD_SHIFT determines the size of the area a second-level page table can map  * PGDIR_SHIFT determines what a third-level page table entry can map  */ #define PMD_SHIFT  21 #define PGDIR_SHIFT  21
```

### 虚拟地址SHIFT宏图：

![](https://img2018.cnblogs.com/blog/970272/201901/970272-20190121112253920-973513645.png)


### 虚拟地址MASK和SIZE宏图：


![](https://img2018.cnblogs.com/blog/970272/201901/970272-20190121112304771-208642558.png)


## 3. Page Table Entry
PTEs, PMDs和PGDs分别由pte_t, pmd_t 和pgd_t来描述。为了存储保护位，pgprot_t被定义，它拥有相关的flags并经常被存储在page table entry低位(lower bits)，其具体的存储方式依赖于CPU架构。

每个pte_t指向一个物理页的地址，并且所有的地址都是页对齐的。因此在32位地址中有PAGE_SHIFT(12)位是空闲的，它可以为PTE的状态位。

### PTE的保护和状态位如下图所示：


![](https://img2018.cnblogs.com/blog/970272/201901/970272-20190121112320508-1386480876.png)


## 4. 如何通过3级页表访问物理内存
为了通过PGD、PMD和PTE访问物理内存，其相关宏在asm/pgtable.h中定义。

* pgd_offset 

根据当前虚拟地址和当前进程的mm_struct获取pgd项的宏定义如下： 

```
/* to find an entry in a page-table-directory */
#define pgd_index(addr)		((addr) >> PGDIR_SHIFT)  //获得在pgd表中的索引
#define pgd_offset(mm, addr)	((mm)->pgd + pgd_index(addr)) //获得pmd表的起始地址
 
/* to find an entry in a kernel page-table-directory */
#define pgd_offset_k(addr)	pgd_offset(&init_mm, addr)
```

* pmd_offset

根据通过pgd_offset获取的pgd 项和虚拟地址，获取相关的pmd项(即pte表的起始地址) 

```
/* Find an entry in the second-level page table.. */
#define pmd_offset(dir, addr)	((pmd_t *)(dir))   //即为pgd项的值
        
```

* pte_offset

根据通过pmd_offset获取的pmd项和虚拟地址，获取相关的pte项(即物理页的起始地址)

```
#ifndef CONFIG_HIGHPTE
#define __pte_map(pmd)		pmd_page_vaddr(*(pmd))
#define __pte_unmap(pte)	do { } while (0)
#else
#define __pte_map(pmd)		(pte_t *)kmap_atomic(pmd_page(*(pmd)))
#define __pte_unmap(pte)	kunmap_atomic(pte)
#endif
 
#define pte_index(addr)		(((addr) >> PAGE_SHIFT) & (PTRS_PER_PTE - 1))
 
#define pte_offset_kernel(pmd,addr)	(pmd_page_vaddr(*(pmd)) + pte_index(addr))
 
#define pte_offset_map(pmd,addr)	(__pte_map(pmd) + pte_index(addr))
#define pte_unmap(pte)			__pte_unmap(pte)
 
#define pte_pfn(pte)		(pte_val(pte) >> PAGE_SHIFT)
#define pfn_pte(pfn,prot)	__pte(__pfn_to_phys(pfn) | pgprot_val(prot))
 
#define pte_page(pte)		pfn_to_page(pte_pfn(pte))
#define mk_pte(page,prot)	pfn_pte(page_to_pfn(page), prot)
 
#define set_pte_ext(ptep,pte,ext) cpu_set_pte_ext(ptep,pte,ext)
#define pte_clear(mm,addr,ptep)	set_pte_ext(ptep, __pte(0), 0)
```

### 其示意图如下图所示：

![](https://img2018.cnblogs.com/blog/970272/201901/970272-20190121112339386-2108956134.png)


## 64位 
上面主要是介绍了32位的 页表转换 逻辑；

现在我们来看看64位的页表转换逻辑， 和32位的区别；
### 区别
1. 32位的是32个bit，64位的是64个bit的虚拟地址；但是这个64位的虚拟地址中不是每一个bit都使用了，现在只使用了48个bit，其中，PGD，PUD，PMD，PTE分别是9个bit，PAGE大小占用12个bit，12个bit刚好是一个page的大小，也就是4k。
2. 需要注意的是，PGD，PUD，PMD，PTE分别都是9个bit，在虚拟地址中，虚拟地址转换到物理地址，是由MMU完成的，MMU根据虚拟地址，分别抽出PGD，PUD，PMD，PTE的值，就可以计算出物理机制。
3. PGD，PUD，PMD，PTE 分别都是一个4k的page，其实，PGD，PUD，PMD，PTE 是四张table，table的大小都是4k，其中table的entry分别是:`pgd_t, pud_t, pmd_t, pte_t`, 都是unsigned long 类型（8个字节），4k（2的12次方）/8 字节 （2的3次方）= 512 个entry（2的9次方）
4. PTE的table大小也是4k，entry大小也是8字节，所以，PTE表中可以存放512个entry（也就是512个物理机地址），8个字节是64位，其中PTE只需要48位就可以了，剩下的12位作为flag，记录，这个pte entry的属性（accessed，present，dirty ...）

### 宏
```
arch/x86/include/asm/page_types.h

#define PAGE_SHIFT      12
#define PAGE_SIZE       (_AC(1,UL) << PAGE_SHIFT)
#define PAGE_MASK       (~(PAGE_SIZE-1))

#define PMD_PAGE_SIZE       (_AC(1, UL) << PMD_SHIFT)
#define PMD_PAGE_MASK       (~(PMD_PAGE_SIZE-1))

#define PUD_PAGE_SIZE       (_AC(1, UL) << PUD_SHIFT)
#define PUD_PAGE_MASK       (~(PUD_PAGE_SIZE-1))
```

#### SHIFT
在`arch/x86/include/asm/pgtable_64_types.h` 中，定义了 64位 x86下的，`pte_t`的类型其实是`pteval_t`, 而 `pteval_t` 其实是 `unsigned long` 类型。其他的也一样都是`unsigned long` , `unsigned long`  在x86_64 下是8个字节。 

```
// PAGE_SHIFT是12位，PMD_SHITT就是21位，刚好，PTE占用了9位
arch/x86/include/asm/pgtable_64_types.h <<PMD_SHIFT>>
#define PMD_SHIFT 21
#define PUD_SHIFT 30

typedef unsigned long   pteval_t;
typedef unsigned long   pmdval_t;
typedef unsigned long   pudval_t;
typedef unsigned long   pgdval_t;
typedef unsigned long   pgprotval_t;

typedef struct { pteval_t pte; } pte_t;

```

```
 32位编译器：

      char ：1个字节
      char*（即指针变量）: 4个字节（32位的寻址空间是2^32, 即32个bit，也就是4个字节。同理64位编译器）
      short int : 2个字节
      int：  4个字节
      unsigned int : 4个字节
      float:  4个字节
      double:   8个字节
      long:   4个字节
      long long:  8个字节
      unsigned long:  4个字节

  64位编译器：

      char ：1个字节
      char*(即指针变量): 8个字节
      short int : 2个字节
      int：  4个字节
      unsigned int : 4个字节
      float:  4个字节
      double:   8个字节
      long:   8个字节
      long long:  8个字节
      unsigned long:  8个字节
```

## 四级分页模型
x86-64架构采用四级分页模型，它是Linux四级分页机制的一个很好的实现。我们将x86-64架构的分页模型作为分析的入口点，它很好的“迎合”了Linux的四级分页机制。稍候我们再分析这种机制如何同样做到适合三级和二级分页模型。

### PGDIR_SHIFT及相关宏

表示线性地址中offset字段、Table字段、Middle Dir字段和Upper Dir字段的位数。`PGDIR_SIZE`用于计算页全局目录中一个表项能映射区域的大小。`PGDIR_MASK`用于屏蔽线性地址中Middle Dir字段、Table字段和offset字段所在位。

在四级分页模型中，`PGDIR_SHIFT`占据39位，即9位页上级目录、9位页中间目录、9位页表和12位偏移。页全局目录同样占线性地址的9位，因此`PTRS_PER_PGD`为512。

```
arch/x86/include/asm/pgtable_64_types.h
#define PGDIR_SHIFT 39
#define PTRS_PER_PGD 512
#define PGDIR_SIZE (_AC(1, UL) << PGDIR_SHIFT)
#define PGDIR_MASK (~(PGDIR_SIZE - 1))
```

### pgd_offset()

该函数返回线性地址address在页全局目录中对应表项的线性地址。mm为指向一个内存描述符的指针，address为要转换的线性地址。该宏最终返回addrress在页全局目录中相应表项的线性地址。

```
arch/x86/include/asm/pgtable.h

#define pgd_index(address) (((address) >> PGDIR_SHIFT) & (PTRS_PER_PGD - 1))

#define pgd_offset(mm, address) ((mm)->pgd + pgd_index((address)))
```

### PUD_SHIFT及相关宏

表示线性地址中offset字段、Table字段和Middle Dir字段的位数。PUD_SIZE用于计算页上级目录一个表项映射的区域大小，`PUD_MASK`用于屏蔽线性地址中Middle Dir字段、Table字段和offset字段所在位。

在64位系统四级分页模型下，`PUD_SHIFT`的大小为30，包括12位的offset字段、9位Table字段和9位Middle Dir字段。由于页上级目录在线性地址中占9位，因此页上级目录的表项数为512。

```
arch/x86/include/asm/pgtable_64_types.h

#define PUD_SHIFT 30
#define PTRS_PER_PUD 512
#define PUD_SIZE        (_AC(1, UL) << PUD_SHIFT)
#define PUD_MASK        (~(PUD_SIZE - 1))
```

## pud_offset()
`pgd_val(pgd)`获得pgd所指的页全局目录项，它与`PTE_PFN_MASK`相与得到该项所对应的物理页框号。`__va()`用于将物理地址转化为虚拟地址。也就是说，`pgd_page_vaddr`最终返回页全局目录项pgd所对应的线性地址。因为`pud_index()`返回线性地址在页上级目录中所在表项的索引，因此`pud_offset()`最终返回addrress对应的页上级目录项的线性地址。

```
arch/x86/include/asm/page.h

#define __va(x)                 ((void *)((unsigned long)(x)+PAGE_OFFSET))

arch/x86/include/asm/pgtable_types.h
#define PTE_PFN_MASK            ((pteval_t)PHYSICAL_PAGE_MASK)
arch/x86/include/asm/pgtable.h
static inline unsigned long pgd_page_vaddr(pgd_t pgd)
{
        return (unsigned long)__va((unsigned long)pgd_val(pgd) & PTE_PFN_MASK);
}
static inline pud_t *pud_offset(pgd_t *pgd, unsigned long address)

{
        return (pud_t *)pgd_page_vaddr(*pgd) + pud_index(address);
}
```

### PMD_SHIFT及相关宏

表示线性地址中offset字段和Table字段的位数，2的`PMD_SHIFT`次幂表示一个页中间目录项可以映射的内存区域大小。`PMD_SIZE`用于计算这个区域的大小，`PMD_MASK`用来屏蔽offset字段和Table字段的所有位。`PTRS_PER_PMD`表示页中间目录中表项的个数。

在64位系统中，Linux采用四级分页模型。线性地址包含页全局目录、页上级目录、页中间目录、页表和偏移量五部分。在这两种模型中`PMD_SHIFT`占21位，即包括Table字段的9位和offset字段的12位。`PTRS_PER_PMD`的值为512，即2的9次幂，表示页中间目录包含的表项个数。

```
#define PMD_SHIFT 21
#define PTRS_PER_PMD 512
#define PMD_SIZE (_AC(1, UL) << PMD_SHIFT)
#define PMD_MASK (~(PMD_SIZE - 1))
```

### pmd_offset()

该函数返回address在页中间目录中对应表项的线性地址。

```
static inline pmd_t *pmd_offset(pud_t *pud, unsigned long address)
{
        return (pmd_t *)pud_page_vaddr(*pud) + pmd_index(address);
}
static inline unsigned long pud_page_vaddr(pud_t pud)
{
        return (unsigned long)__va((unsigned long)pud_val(pud) & PTE_PFN_MASK);
}
```

### PAGE_SHIFT及相关宏

表示线性地址offset字段的位数。该宏的值被定义为12位，即页的大小为4KB。与它对应的宏有`PAGE_SIZE`，它返回一个页的大小；`PAGE_MASK`用来屏蔽offset字段，其值为oxfffff000。`PTRS_PER_PTE`表明页表在线性地址中占据9位。

```
arch/x86/include/asm/page_types.h

/* PAGE_SHIFT determines the page size */
#define PAGE_SHIFT 12
#define PTRS_PER_PTE    512
#define PAGE_SIZE (_AC(1,UL) << PAGE_SHIFT)
#define PAGE_MASK (~(PAGE_SIZE-1))
```

通过上面的分析可知，在x86-64架构下64位的线性地址被划分为五部分，每部分占据的位数分别为9，9，9，9，12，实际上只用了64位中的48位。对于四级页表而言，级别从高到底每级页表中表项的个数为512，512，512，512。


## Refs

https://wenku.baidu.com/view/c565e26da98271fe910ef970.html

https://blog.csdn.net/shuningzhang/article/details/38090695
