---
layout: post
title: "In-depth code research - alloc_pages"
author: muahao
tags:
- memory
- kernel
---

## 申请一个页块(page block: which order=x）

From kernel-4.9

### Summary
page block 是指一个order=x的连续的page， `alloc_pages` 是内核申请分配内存的主要入口，在申请内存时，首先会确定一个prefer zone，还有一些backup zone list，期望，从中
申请到 page block

这里有两个分配逻辑，“快分配”（`get_page_from_freelist`） 和“慢分配” （`__alloc_pages_slowpath`）, 不过肯定“快分配” 是热点

在进入“快分配”后，如果申请的是order=0 的单page block，为了效率，zone中设计了一个per cpu缓存（`zone->pageset->pcp->lists[MIGRATE_PCPTYPES]`），这里分别为几种`MIGRATE_PCPTYPES` 的page保留了一些缓存，当申请单个page的时候，会先从这个缓存中分配，如果没有，则再从buddy system中进货到这里。

如果申请的是order>0 的page block，则会直接从 buddy system (`zone->free_area[order]->free_list[migratetype]` ) 获取指定order的page block。

如果在“快分配”阶段没有分配到内存，则才会在进入“慢分配”，在“慢分配”阶段，会先启动`kswapd`初步尝试回收一些内存，然后再调用“快分配”（`get_page_from_freelist`）如果还是没有，则会进行“内存压缩” （compaction）操作。


### Call chain
```
__get_free_pages                          <EXPORT_SYMBOL>
    alloc_pages
        alloc_pages_current               <EXPORT_SYMBOL>
            __alloc_pages_nodemask        <核心函数> <EXPORT_SYMBOL> <From zone to alloc>
                1. get_page_from_freelist <likely>
                    for_next_zone_zonelist_nodemask { // 指定一个zone
                        if (order = 0) {
                            buffered_rmqueue //当order=0时，调用这个函数首先看此cpu上的pcp缓存有没有page缓存，如果没有,会先从free area进货
                                page = list_last_entry(list, struct page, lru);
                        } else {
                            spin_lock_irqsave(&zone->lock, flags);
                            __rmqueue_smallest(zone, order, MIGRATE_HIGHATOMIC);  // 从zone->free_area[order]->free_list[migratetype] 获取指定order的page
                                expand
                            __rmqueue                                             // 和__rmqueue_smallest 不同在于migratetype
                            spin_unlock(&zone->lock);
                        }
                    }
                2. __alloc_pages_slowpath <unlikely>
				       gfp_to_alloc_flags             // 调整alloc_flags分配参数
                       wake_all_kswapds               // 启动kswapd 压缩内存 (compaction), kswapd在alloc_page过程中内存不足时被启动
                       get_page_from_freelist         // 再次尝试快速分配, 分配成功则返回，失败，则继续
                       2.1 __alloc_pages_direct_reclaim   // 直接回收(Direct Reclaim)
                             __perform_reclaim
                             lockdep_set_current_reclaim_state(gfp_mask);  // 上锁current->lockdep_reclaim_gfp = gfp_mask;
                                 try_to_free_pages      // 准备struct scan_control sc
                                     do_try_to_free_pages // 直接回收函数入口
                                         (struct scan_control sc); // Build sc
                                         shrink_zones(zonelist, sc)
                                             for_each_zone_zonelist_nodemask{
                                                 if (global_reclaim(sc)) { // 如果没有目标memcg（sc->target_mem_cgroup) 或者没有没有开启memcg
                                                     mem_cgroup_soft_limit_reclaim
                                                 }
                                                 shrink_node(zone->zone_pgdat, sc) // 将这个node上的所有的zone,遍历回收.
                                                     shrink_node_memcg             // 指定一个memcg(kswapd & Direct reclaim都会使用)
                                                         get_scan_count            // 这里使用nr保存每个lru回收多少内存
                                                         while(nr[LRU_INACTIVE_ANON]||nr[LRU_ACTIVE_FILE]||nr[INACTIVE_FILE]]) {
                                                             for_each_evictable_lru{
                                                                 shrink_list               // 从lru中回收,指定了lru:LRU_INACTIVE_ANON, LRU_ACTIVE_FILE, LRU_INACTIVE_FILE, 这里调用for_each_evictable_lru，只从上面指定的lru中回收
                                                             }
                                                             cond_resched();
                                                         }
                                                     shrink_slab
                                             }
                             lockdep_clear_current_reclaim_state();        // 解锁 current->lockdep_reclaim_gfp
                             get_page_from_freelist     // “快分配”
                       2.2 __alloc_pages_direct_compact   // 分配成功则返回page，失败，则开始direct page compaction
                             psi_memstall_enter
                             start = ktime_get_ns();
                             try_to_compact_pages        // "内存压缩"的主函数, 返回"压缩状态"(enum compact_result)
                                 for_each_zone_zonelist_nodemask { // 尝试zonelist中的每个zone进行内存压缩
                                     status = compact_zone_order() // 这个函数里主要初始化一个struct compact_control结构体，然后调用compact_zone()：
                                         compact_zone              // 对一个zone进行内存压缩
                                     if (status == COMPACT_SUCCESS) {
                                         compaction_defer_reset(zone, order, false)
                                     }
                                 }
                             end = ktime_get_ns();
                             memcg_lat_count(COMPACT_DR, end - start);
                             psi_memstall_leave
                             get_page_from_freelist      // 从buddy system中再次尝试快速分配
                             if (page) {
                                 count_vm_event(COMPACTSUCCESS); // 如果成功，则统计一下
                             } else {
                                 count_vm_event(COMPACTFAIL); // 如果失败，也统计一下
                             }
                       2.3 __alloc_pages_may_oom          // compaction，reclaim失败后，只能oom了

```

### 分配page block的核心函数 - `__alloc_pages_nodemask`
```
/*
 * 1. zonelist是一组zone，分配内存是需要发生在一个zone上
 * 2. ac 上下文将会记录 prefer zone
 */
__alloc_pages_nodemask(gfp_t gfp_mask, unsigned int order,
            struct zonelist *zonelist, nodemask_t *nodemask)
{
    struct page *page;
    unsigned int alloc_flags = ALLOC_WMARK_LOW;
    gfp_t alloc_mask = gfp_mask; /* The gfp_t that was actually used for allocation */
    struct alloc_context ac = {
        .high_zoneidx = gfp_zone(gfp_mask),
        .zonelist = zonelist,
        .nodemask = nodemask,
        .migratetype = gfpflags_to_migratetype(gfp_mask),
    };

    ...

    if (!ac.preferred_zoneref->zone) {
        page = NULL;
        goto no_zone;
    }
    ac.preferred_zoneref = first_zones_zonelist(ac.zonelist,
                    ac.high_zoneidx, ac.nodemask);  /* Fetch a prefer zone */
    page = get_page_from_freelist(alloc_mask, order, alloc_flags, &ac); /* 从zone的freelist中分配 */
    ...

no_zone:
    page = __alloc_pages_slowpath(alloc_mask, order, &ac);              /* 从buddy分配 */
}
```


### 从pcp中分配一个page block- buffered_rmqueue
```
struct per_cpu_pages {
    int count;      /* number of pages in the list */
    int high;       /* high watermark, emptying needed */
    int batch;      /* chunk size for buddy add/remove */

    /* Lists of pages, one per migrate type stored on the pcp-lists */
    struct list_head lists[MIGRATE_PCPTYPES];
};

static inline
struct page *buffered_rmqueue(struct zone *preferred_zone,
            struct zone *zone, unsigned int order,
            gfp_t gfp_flags, unsigned int alloc_flags,
            int migratetype)
{
    unsigned long flags;
    struct page *page;
    bool cold = ((gfp_flags & __GFP_COLD) != 0);

    if (likely(order == 0)) {    /* 如果，分配order=0的page */
        struct per_cpu_pages *pcp;
        struct list_head *list;

        local_irq_save(flags);
        do {
            pcp = &this_cpu_ptr(zone->pageset)->pcp; /* 从pcp中获取 */
            list = &pcp->lists[migratetype];         /* 获取pcp的list */
            if (list_empty(list)) {
                pcp->count += rmqueue_bulk(zone, 0,
                        pcp->batch, list,
                        migratetype, cold);
                if (unlikely(list_empty(list)))
                    goto failed;
            }

            if (cold)
                page = list_last_entry(list, struct page, lru); /* (从pcp中申请) pcp是个list，要么从头获取一个page，要么从尾获取一个page */
            else
                page = list_first_entry(list, struct page, lru);

            list_del(&page->lru);
            pcp->count--;

        } while (check_new_pcp(page));
    } else {                     /* 如果，分配的不是order=0的page */

        WARN_ON_ONCE((gfp_flags & __GFP_NOFAIL) && (order > 1));
        spin_lock_irqsave(&zone->lock, flags); /* zone->lock上锁 */

        do {
            page = NULL;
            if (alloc_flags & ALLOC_HARDER) {
                page = __rmqueue_smallest(zone, order, MIGRATE_HIGHATOMIC); // (从buddy system申请), 先从migratetype=MIGRATE_HIGHATOMIC的list中申请
                if (page)
                    trace_mm_page_alloc_zone_locked(page, order, migratetype);
            }
            if (!page)
                page = __rmqueue(zone, order, migratetype); /* (从buddy system中申请) 再从migratetype中申请 */
        } while (page && check_new_pages(page, order));
        spin_unlock(&zone->lock);
        if (!page)
            goto failed;
        __mod_zone_freepage_state(zone, -(1 << order),
                      get_pcppage_migratetype(page));
    }

    __count_zid_vm_events(PGALLOC, page_zonenum(page), 1 << order);
    zone_statistics(preferred_zone, zone, gfp_flags);
    local_irq_restore(flags);

    VM_BUG_ON_PAGE(bad_range(zone, page), page);
    return page;

failed:
    local_irq_restore(flags);
    return NULL;
}

```

### 从buddy system申请page block - `__rmqueue_smallest`
#### 函数__rmqueue_smallest - 从zone->free_area[order]->free_list[migratetype] 获取指定order的page

从buddy system中分配一个(order>1) 的连续页块, 主要是由函数`__rmqueue_smallest` 来完成的

该函数从参数指定的 order 开始寻找页块，如果当前`current_order`对应的链表为空，则继续向下一级寻找。一个 2^(k+1) 页的页块中肯定包含 2^k 页的页块.

如果找到了一个页块，则把它从`current_order`链表中摘下来，相应的递减nr_free的值，更新该zone的统计信息中空闲页的计数。

```
/*
 * Go through the free lists for the given migratetype and remove
 * the smallest available page from the freelists
 */
static inline
struct page *__rmqueue_smallest(struct zone *zone, unsigned int order,
                        int migratetype)
{
    unsigned int current_order;
    struct free_area *area;
    struct page *page;

    /* Find a page of the appropriate size in the preferred list */
    for (current_order = order; current_order < MAX_ORDER; ++current_order) {
        area = &(zone->free_area[current_order]);
        page = list_first_entry_or_null(&area->free_list[migratetype],
                            struct page, lru);
        if (!page)
            continue;
        list_del(&page->lru);
        rmv_page_order(page);
        area->nr_free--;
        /* 如果当前current_order比参数指定的 order 大，则从buddy system中摘下链表的这个页块就要被分成若干小的页块，除去要分配的这一块，其他的还得放回buddy system。这个工作是通过函数 expand 来完成的。*/
        expand(zone, page, order, current_order, area, migratetype);
        set_pcppage_migratetype(page, migratetype);
        return page;
    }

    return NULL;
}

```
### 慢分配

```
static inline struct page *
__alloc_pages_slowpath(gfp_t gfp_mask, unsigned int order,
                        struct alloc_context *ac)
{
    bool can_direct_reclaim = gfp_mask & __GFP_DIRECT_RECLAIM;
    struct page *page = NULL;
    unsigned int alloc_flags;
    unsigned long did_some_progress;
    enum compact_priority compact_priority;
    enum compact_result compact_result;
    int compaction_retries;
    int no_progress_loops;
    unsigned int cpuset_mems_cookie;

	/* 检查order是否非法 */
    if (order >= MAX_ORDER) {
        WARN_ON_ONCE(!(gfp_mask & __GFP_NOWARN));
        return NULL;
    }

    /*
     * We also sanity check to catch abuse of atomic reserves being used by
     * callers that are not in atomic context.
     */
    if (WARN_ON_ONCE((gfp_mask & (__GFP_ATOMIC|__GFP_DIRECT_RECLAIM)) ==
                (__GFP_ATOMIC|__GFP_DIRECT_RECLAIM)))
        gfp_mask &= ~__GFP_ATOMIC;

retry_cpuset:
    compaction_retries = 0;
    no_progress_loops = 0;
    compact_priority = DEF_COMPACT_PRIORITY;
    cpuset_mems_cookie = read_mems_allowed_begin();
    /*
     * We need to recalculate the starting point for the zonelist iterator
     * because we might have used different nodemask in the fast path, or
     * there was a cpuset modification and we are retrying - otherwise we
     * could end up iterating over non-eligible zones endlessly.
     */
    ac->preferred_zoneref = first_zones_zonelist(ac->zonelist,
                    ac->high_zoneidx, ac->nodemask);
    if (!ac->preferred_zoneref->zone)
        goto nopage;


    /*
     * The fast path uses conservative alloc_flags to succeed only until
     * kswapd needs to be woken up, and to avoid the cost of setting up
     * alloc_flags precisely. So we do that now.
     */
	/* 调整alloc_flags 分配标志，稍微降低分配标准以便这次调用get_page_from_freelist()有可能分配到内存。 */
    alloc_flags = gfp_to_alloc_flags(gfp_mask);

	/* 唤醒每个zone所属node中的kswapd守护进程。这个守护进程负责换出很少使用的页，以提高目前系统可以用的空闲页框。在kswapd交换进程被唤醒之后，该函数开始尝试新一轮的分配。 */
    if (gfp_mask & __GFP_KSWAPD_RECLAIM)
        wake_all_kswapds(order, ac);

    /*
     * The adjusted alloc_flags might result in immediate success, so try
     * that first
     */
	/* 也许freelist中有page了, 再尝试一次, 如果分配到了，就return 出去。 */
    page = get_page_from_freelist(gfp_mask, order, alloc_flags, ac);
    if (page)
        goto got_pg;

    /*
     * For costly allocations, try direct compaction first, as it's likely
     * that we have enough base pages and don't need to reclaim. Don't try
     * that for allocations that are allowed to ignore watermarks, as the
     * ALLOC_NO_WATERMARKS attempt didn't yet happen.
     */
	/* 这里要动真格了，需要先回收内存 */
    if (can_direct_reclaim && order > PAGE_ALLOC_COSTLY_ORDER &&
        !gfp_pfmemalloc_allowed(gfp_mask)) {
        page = __alloc_pages_direct_compact(gfp_mask, order,
                        alloc_flags, ac,
                        INIT_COMPACT_PRIORITY,
                        &compact_result);
        if (page)
            goto got_pg;

        /*
         * Checks for costly allocations with __GFP_NORETRY, which
         * includes THP page fault allocations
         */
        if (gfp_mask & __GFP_NORETRY) {
            /*
             * If compaction is deferred for high-order allocations,
             * it is because sync compaction recently failed. If
             * this is the case and the caller requested a THP
             * allocation, we do not want to heavily disrupt the
             * system, so we fail the allocation instead of entering
             * direct reclaim.
             */
            if (compact_result == COMPACT_DEFERRED)
                goto nopage;

            /*
             * Looks like reclaim/compaction is worth trying, but
             * sync compaction could be very expensive, so keep
             * using async compaction.
             */
            compact_priority = INIT_COMPACT_PRIORITY;
        }
    }

```

### 内存压缩 - `try_to_compact_pages`
1. 内存压缩不是内存回收
2. 尝试zonelist中的每个zone进行内存压缩
3. order: 2的次方，如果是分配时调用到，这个就是分配时希望获取的order，如果是通过写入/proc/sys/vm/compact_memory文件进行强制内存压缩，order就是-1
4. 返回的是“内存压缩” 状态“compact_result”
5. 压缩是有成本的，不是想压缩就压缩，COMPACT_SKIPPED 就代表跳过这次压缩

```
enum compact_result try_to_compact_pages(gfp_t gfp_mask, unsigned int order,
        unsigned int alloc_flags, const struct alloc_context *ac,
        enum compact_priority prio)
{
    /* 表示能够使用文件系统的IO操作 */
    int may_enter_fs = gfp_mask & __GFP_FS;
    /* 表示可以使用磁盘的IO操作 */
    int may_perform_io = gfp_mask & __GFP_IO;
    struct zoneref *z;
    struct zone *zone;
    enum compact_result rc = COMPACT_SKIPPED;

    /* Check if the GFP flags allow compaction */
    /* 不允许使用文件系统IO和磁盘IO，则跳过本次压缩，因为不使用IO有可能导致死锁*/
    if (!may_enter_fs || !may_perform_io)
        return COMPACT_SKIPPED;

    trace_mm_compaction_try_to_compact_pages(order, gfp_mask, prio);

    /* Compact each zone in the list */
    for_each_zone_zonelist_nodemask(zone, z, ac->zonelist, ac->high_zoneidx,
                                ac->nodemask) {
        enum compact_result status;

        if (prio > MIN_COMPACT_PRIORITY
                    && compaction_deferred(zone, order)) {
            rc = max_t(enum compact_result, COMPACT_DEFERRED, rc);
            continue;
        }

        /* 压缩 */
        status = compact_zone_order(zone, order, gfp_mask, prio,
                    alloc_flags, ac_classzone_idx(ac));
        rc = max(status, rc);

        /* The allocation should succeed, stop compacting */
        if (status == COMPACT_SUCCESS) {
            /*
             * We think the allocation will succeed in this zone,
             * but it is not certain, hence the false. The caller
             * will repeat this with true if allocation indeed
             * succeeds in this zone.
             */
            compaction_defer_reset(zone, order, false);

            break;
        }

        if (prio != COMPACT_PRIO_ASYNC && (status == COMPACT_COMPLETE ||
                    status == COMPACT_PARTIAL_SKIPPED))
            /*
             * We think that allocation won't succeed in this zone
             * so we defer compaction there. If it ends up
             * succeeding after all, it will be reset.
             */
            defer_compaction(zone, order);

        /*
         * We might have stopped compacting due to need_resched() in
         * async compaction, or due to a fatal signal detected. In that
         * case do not try further zones
         */
        if ((prio == COMPACT_PRIO_ASYNC && need_resched())
                    || fatal_signal_pending(current))
            break;
    }

    return rc;
}

```

### 直接回收 - `try_to_free_pages` -> `shrink_zones`

```

unsigned long try_to_free_pages(struct zonelist *zonelist, int order,
                gfp_t gfp_mask, nodemask_t *nodemask)
{
    unsigned long nr_reclaimed;
    u64 start;
    struct scan_control sc = {
        .nr_to_reclaim = SWAP_CLUSTER_MAX,
        .gfp_mask = memalloc_noio_flags(gfp_mask),
        .reclaim_idx = gfp_zone(gfp_mask),
        .order = order,
        .nodemask = nodemask,
        .priority = DEF_PRIORITY,
        .may_writepage = !laptop_mode,
        .may_unmap = 1,
        .may_swap = 1,
    };

    /*
     * Do not enter reclaim if fatal signal was delivered while throttled.
     * 1 is returned so that the page allocator does not OOM kill at this
     * point.
     */
    if (throttle_direct_reclaim(sc.gfp_mask, zonelist, nodemask))
        return 1;

    trace_mm_vmscan_direct_reclaim_begin(order,
                sc.may_writepage,
                sc.gfp_mask,
                sc.reclaim_idx);


    start = ktime_get_ns();
    nr_reclaimed = do_try_to_free_pages(zonelist, &sc);

    trace_mm_vmscan_direct_reclaim_end(nr_reclaimed);

    memcg_lat_count(GLOBAL_DR, (ktime_get_ns() - start));

    return nr_reclaimed;
}
```


```
static void shrink_zones(struct zonelist *zonelist, struct scan_control *sc)
{
    struct zoneref *z;
    struct zone *zone;
    unsigned long nr_soft_reclaimed;
    unsigned long nr_soft_scanned;
    gfp_t orig_mask;
    pg_data_t *last_pgdat = NULL;

    /*
     * If the number of buffer_heads in the machine exceeds the maximum
     * allowed level, force direct reclaim to scan the highmem zone as
     * highmem pages could be pinning lowmem pages storing buffer_heads
     */
    orig_mask = sc->gfp_mask;
    if (buffer_heads_over_limit) {
        sc->gfp_mask |= __GFP_HIGHMEM;
        sc->reclaim_idx = gfp_zone(sc->gfp_mask);
    }

    for_each_zone_zonelist_nodemask(zone, z, zonelist,
                    sc->reclaim_idx, sc->nodemask) {
        /*
         * Take care memory controller reclaiming has small influence
         * to global LRU.
         */
        if (global_reclaim(sc)) {
            if (!cpuset_zone_allowed(zone,
                         GFP_KERNEL | __GFP_HARDWALL))
                continue;

            /* 当还可以compaction时，不回收*/
            if (IS_ENABLED(CONFIG_COMPACTION) &&
                sc->order > PAGE_ALLOC_COSTLY_ORDER &&
                compaction_ready(zone, sc)) {
                sc->compaction_ready = true;
                continue;
            }

            /* 当zone->zone_pgdat == last_pgdat， 不回收 */
            if (zone->zone_pgdat == last_pgdat)
                continue;

            nr_soft_scanned = 0;
            /* 回收 */
            nr_soft_reclaimed = mem_cgroup_soft_limit_reclaim(zone->zone_pgdat,
                        sc->order, sc->gfp_mask,
                        &nr_soft_scanned);
            sc->nr_reclaimed += nr_soft_reclaimed;
            sc->nr_scanned += nr_soft_scanned;
            /* need some check for avoid more shrink_zone() */
        }

        /* See comment about same check for global reclaim above */
        if (zone->zone_pgdat == last_pgdat)
            continue;
        last_pgdat = zone->zone_pgdat;
        shrink_node(zone->zone_pgdat, sc);
    }

    /*
     * Restore to original mask to avoid the impact on the caller if we
     * promoted it to __GFP_HIGHMEM.
     */
    sc->gfp_mask = orig_mask;
}

```


```
static bool shrink_node(pg_data_t *pgdat, struct scan_control *sc)
{
    unsigned long nr_reclaimed, nr_scanned;
    bool reclaimable = false;

    do {
        struct mem_cgroup *root = sc->target_mem_cgroup;
        struct mem_cgroup_reclaim_cookie reclaim = {
            .pgdat = pgdat,
            .priority = sc->priority,
        };
        struct mem_cgroup = *memcg;

        memset(&sc->nr, 0, sizeof(sc->nr));

        nr_reclaimed = sc->nr_reclaimed;
        nr_scanned = sc->nr_scanned;

        memcg = mem_cgroup_iter(root, NULL, &reclaim);
        do {
           reclaimed = sc->nr_reclaimed;
           scanned = sc->nr_scanned;
           shrink_node_memcg(pgdat, memcg, sc, &lru_pages); // 回收
           node_lru_pages += lru_pages
           if (memcg)
            shrink_slab(sc->gfp_mask, pgdat->node_id,
                    memcg, sc->nr_scanned - scanned,
                    lru_pages);
        } while ((memcg = mem_cgroup_iter(root, memcg, &reclaim)));
    } while (should_continue_reclaim(pgdat, sc->nr_reclaimed - nr_reclaimed,
                     sc->nr_scanned - nr_scanned, sc));
}
```
