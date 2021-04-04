---
layout: post
title: "In-depth code research - pgfault"
author: muahao
excerpt: In-depth code research - pgfault
tags:
- memory
---


## pgfault
From: kernel-4.9

```

do_page_fault
   __do_page_fault
                                    缺页异常分类：1.内核态缺页异常，2.用户态缺页异常
      fault_in_kernel_space				# [1] fault happen in kernel space
                                     内核态异常分为:
                                    1.vmalloc区异常，因为非vmalloc的内核区是直接对等映射的，只有vmalloc区是动态映射的。而vmalloc出现异常比较好处理，只需要页表同步就可以了（因为伴随着进程的切换可能用户进程的页表不是最新的，需要将内核的页表更新到用户进程的页表）
                                    2.内核引用用户空间地址发生的异常，比如用户态的地址非法，或者页面已经被交换到了磁盘。
                                    3.内核bug。内核态缺页异常频率很低，因为内核态的数据不会换出到磁盘的。所以用户态才会经常出现缺页异常，因为用户态的数据经常写到交换区和文件。并且在进程刚创建运行时也会伴随着大量的缺页异常。
         vmalloc_fault
      find_vma                        # [2] fault happen in user space; Ref: https://blog.csdn.net/m0_37962600/article/details/81448553
        |-寻找触发异常address，是否属于此用户态进程的vma中，属于则进入good_area，不属于（越界）则进入bad_area流程。
      expand_stack
         expand_downwards
            anon_vma_prepare
      <good_area>:
      handle_mm_fault              # 用于实现页面分配与交换，good_area中的操作。
         |- 它分为两个步骤：首先，如果页表不存在或被交换出，则要首先分配页面给页表；然后才真正实施页面的分配，并在页表上做记录。具体如何分配这个页框是通过调用handle_pte_fault()完成的。
         hugetlb_fault
         __handle_mm_fault
            pgd_offset
            pud_alloc
            pmd_alloc
            create_huge_pmd
               do_huge_pmd_anonymous_page
                  < readonly case >			# [3] Hugepage - readonly
                  __do_huge_pmd_anonymous_page		# [4] Hugepage - write
               vma->vm_ops->pmd_fault
            do_huge_pmd_numa_page			# [5] Hugepage - AutoNUMA
            wp_huge_pmd					# [6] Hugepage - write-protected
            handle_pte_fault
                |- 函数根据页表项pte所描述的物理页框是否在物理内存中，分为两大类：
                    （1）请求调页：被访问的页框不在主存中，那么此时必须分配一个页框，分为线性映射、非线性映射、swap情况下映射
                    （2）写实复制：被访问的页存在，但是该页是只读的，内核需要对该页进行写操作，此时内核将这个已存在的只读页中的数据复制到一个新的页框中

                handle_pte_fault()调用pte_none()检查表项是否为空，即全为0；如果为空就说明映射尚未建立，此时调用do_no_page()来建立内存页面与交换文件的映射；反之，如果表项非空，说明页面已经映射，只要调用do_swap_page()将其换入内存即可；
               do_anonymous_page			# [7] Page - Anon
               do_fault					# [8] Page - File mapped
               do_swap_page				# [9] Page - Swap
                  swapin_readahead
                     read_swap_cache_async
                        __read_swap_cache_async
                           find_get_page
                           alloc_page_vma
                           swapcache_prepare
                           __add_to_swap_cache
                           lru_cache_add_anon
                        swap_readpage
                           frontswap_load
                              __frontswap_load
                                 __frontswap_test
                                 zswap_frontswap_load
                                    zswap_entry_find_get
                                    zpool_map_handle
                                       zbud_zpool_map
                                          zbud_map
                                    crypto_comp_decompress
                                    zpool_unmap_handle
                                       zbud_zpool_unmap
                                          zbud_unmap
                                    zswap_entry_put
                                       zswap_rb_erase
                                       zswap_free_entry
                                          zpool_free
                                             zbud_zpool_free
                                                zbud_free
                                          zswap_pool_put
                                          zswap_entry_cache_free
                                          zswap_update_total_size
               do_numa_page				# [10] Page - AutoNUMA

```

## Ref
https://blog.csdn.net/a7980718/article/details/80895302
