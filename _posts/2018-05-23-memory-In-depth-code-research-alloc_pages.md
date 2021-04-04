---
layout: post
title: "In-depth code research - slub"
author: muahao
excerpt: In-depth code research - slub
tags:
- memory
---

### kmem_cache_init

```
kmem_cache_init
   boot_kmem_cache <tmp variable>
   boot_kmem_cache_node <tmp variable>
   create_boot_cache
   bootstrap
   create_kmalloc_caches
      for(KMALLOC_SHIFT_LOW=3, KMALLOC_SHIFT_HIGH=13) //order, means kmalloc
           can apply for 8B-8KB, get kmalloc_caches array restore kmem_cache
         kmalloc_caches[i]
             create_kmalloc_cache
   init_freelist_randomization


const struct kmalloc_info_struct kmalloc_info[] __initconst = {
    {NULL,                      0},     {"kmalloc-96",             96},
    {"kmalloc-192",           192},     {"kmalloc-8",               8},
    {"kmalloc-16",             16},     {"kmalloc-32",             32},
    {"kmalloc-64",             64},     {"kmalloc-128",           128},
    {"kmalloc-256",           256},     {"kmalloc-512",           512},
    {"kmalloc-1024",         1024},     {"kmalloc-2048",         2048},
    {"kmalloc-4096",         4096},     {"kmalloc-8192",         8192},
    {"kmalloc-16384",       16384},     {"kmalloc-32768",       32768},
    {"kmalloc-65536",       65536},     {"kmalloc-131072",     131072},
    {"kmalloc-262144",     262144},     {"kmalloc-524288",     524288},
    {"kmalloc-1048576",   1048576},     {"kmalloc-2097152",   2097152},
    {"kmalloc-4194304",   4194304},     {"kmalloc-8388608",   8388608},
    {"kmalloc-16777216", 16777216},     {"kmalloc-33554432", 33554432},
    {"kmalloc-67108864", 67108864}
};

eg:
kmalloc(17, GFP_KERNEL)  will alloc from kmalloc-32
```


### kmalloc (big chunk)
```
kmalloc
   kmalloc_large
      kmalloc_order_trace
         kmalloc_order_trace
            kmalloc_order
               alloc_pages
                  alloc_pages_current
                      <follow buddy allocator>
```


### kmalloc (small chunk)
```
* I. kmem_cache --- list: slab_caches
* II. kmem_cache_nodes --- s->node: Array
* III. kmem_cache_cpu --- s->cpu_slab: just a pointer

*IMPORTANT
struct kmem_cache_cpu {
    struct page *page;  // A pointer point to current page
    struct page *partial;  // A list of page OR you can think it's a list of slab
}


kmalloc
   __kmalloc
      kmalloc_slab
         kmalloc_caches | kmalloc_dma_caches
      slab_alloc
         slab_alloc_node <Fast path>
            slab_pre_alloc_hook
            |  memcg_kmem_get_cache
            |
            +----------------+
                             |
                             |
              Init object=kmem_cache_cpu's freelist head
             if (unlikely(!object || !node_match(page, node)))
           /*If there is no available kmem_cache_cpu's freelist will goto Slow-path*/
                             |
                             |
     +---------------+-------+
     |               |
     |              (2) <Slow-path>
     |               __slab_alloc
     |                  local_irq_save
     |                  ___slab_alloc //return freelist
     |                    new_slab:
     |                      2.1 -----------
     |                          //If cpu's partial available <CPU_PARTIAL_ALLOC>
     |                          page=partial;partial=page->next;
     |                          redo
     |                      2.2 -----------
     |                          //If cpu's partial used up
     |                         new_slab_objects //get new freelist
     |                            get_partial
     |                               get_partial_node
     |                               get_any_partial
     |                                  get_partial_node
     |                            new_slab
     |                               allocate_slab
     |                                  alloc_slab_page
     |                                     <alloc from buddy>
     |                  local_irq_restore
     |
     |
     |
     |
     (1) <Fast-path>
           Abstract: per-cpu-variable (struct kmem_cache_cpu)
                     freelist object: A B C D ....  (fetch A)
     get_freepointer_safe     // Start find next_object from c->freelist;
        1. get_freepointer
              freelist_dereference
                 freelist_ptr
        2. freelist_ptr
     prefetch_freepointer   (prefetch B)
        prefetch
           freelist_dereference
     +----------------+-----------------+
                      |
                      memset
                                      slab_post_alloc_hook

```

### ___slab_alloc
; if no page in the kmem_cache_cpu, we try to pick one page
     from the partial list. If we don't have free page in the
     partial list either, then we're going to allocate from
     buddy.



### kfree
```
kfree
   virt_to_head_page
   slab_free
      slab_free_freelist_hook
      do_slab_free
           |
           +------------------+
                              |
           +------------------+-------------------+
           |                                      |
           __slab_free <slow-path>                set_freepointer<fast-path>
           stat(s, FREE_SLOWPATH);                stat(s, FREE_FASTPATH);

```
### kmem_cache_free
```
   cache_from_obj //if free one of kmem_cache(cachepA)'s object's address, first get
the page the object belong to, then check cachepB->name(the cachepB is from
page->slab_cache) == cachepA->name
   virt_to_head_page //from object's linear address to get the page belong to
   slab_free // free an object(a memory area) start from this object's address
to NULL, cnt is 1,
      slab_free_freelist_hook
      do_slab_free
         set_freepointer <fast-path> //page==c->page  stat(s, FREE_FASTPATH);
         __slab_free <slow-path>  // stat(s, FREE_SLOWPATH);
             put_cpu_partial    // stat(s, CPU_PARTIAL_FREE);
             was_frozen         // stat(s, FREE_FROZEN);


```

### kmem_cache_create
```
* 1. kmem_cache --> list: slab_caches
* 2. kmem_cache_nodes
* 3. kmem_cache_cpu

kmem_cache_create <mm/slab_common.c>
   get_online_cpus
   get_online_mems
   memcg_get_cache_ids
   mutex_lock
   kmem_cache_sanity_check
   create_cache
      init_memcg_params
      __kmem_cache_create <mm/slub.c>
         kmem_cache_open // 1. kmem_cache
            calculate_sizes //s->size, s->object->size, s->offset;
                            //s->oo, s->max, s->min struct kmem_cache_order_objects
                            //order: determine page count
                            //object: determine object count per slab
            set_min_partial
            set_cpu_partial // <CONFIG_SLUB_CPU_PARTIAL> ;setup cpu_partial's
                            // value, cpu_partial determined the maximum number
                            // of objects kept in the per cpu partial lists of a processor.
            init_cache_random_seq
            init_kmem_cache_nodes   // 2. s->kmem_cache_node
                early_kmem_cache_node_alloc //n->partial, @__add_partial
                    new_slab  <return a page>
                        allocate_slab
                            alloc_slab_page   <alloc from buddy>
                                * alloc_pages
                                * __alloc_pages_node
                kmem_cache_alloc_node
                   slab_alloc_node
                free_kmem_cache_nodes
            alloc_kmem_cache_cpus // 3. s->cpu_slab
               __alloc_percpu // Init per-cpu-variable s->cpu_slab "struct kmem_cache_cpu"
               init_kmem_cache_cpus
                  init_tid
            free_kmem_cache_nodes
         memcg_propagate_slab_attrs
         sysfs_slab_add <CONFIG_SYSFS>
      list_add(&s->list, &slab_caches);

```
### kmem_cache_alloc
```
kmem_cache_alloc <mm/slub.c>
   slab_alloc
      slab_alloc_node <fast path>
         slab_pre_alloc_hook
      __slab_alloc  <slow path>


slab_proc_init
   proc_create
      proc_slabinfo_operations

slab_show
   cache_show
      get_slabinfo
```


### Think deeply
* per cpu page
* per cpu partial
* per cpu full
* node partail

* when free an object, if the object is from node partial

* When all objects is used up(include node-partial), now we need to alloc new
  page from buddy, then how many pages memory alloctor will alloc? when we get
  the page, where the page should attach? per-cpu-page? per-cpu-partial?

* How to manage per-cpu-full?
* How many partails in per-cpu-partail?
* How many partials in node-partial?
* What factors determine the node-partials count?
