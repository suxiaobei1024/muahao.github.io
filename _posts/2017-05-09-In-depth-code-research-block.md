---
layout: post
title: "In-depth code research - block (request, bio, q)"
author: Ahao Mu
tags:
- kernel
- block
---

# Linux kernel block layer code analyse
## Important struct in blocker layer
* bio
* request:(rq)
* request_queue:(q)
* request_list:(rl)   rl = blk_get_rl(q, bio);

```
struct bio {
    unsigned int bi_opf;
    unsigned short bi_flags;
    blk_status_t bi_status;
}
struct request {
    struct list_head queuelist;       --- list: plug_list
    struct request_queue *q;
    rq_end_io_fn *end_io;   /* completion callback */
    sector_t __sector;
    struct bio *bio;

    #ifdef CONFIG_BLK_WBT
    unsigned short wbt_flags;
    #endif
}

struct request_queue {
    struct elevator_queue  *elevator;
    struct request_list *rl;
}

struct request_list {
    struct request_queue *q; /* the queue the request_list belongs to */
}

struct blk_plug {
    struct list_head list; /* requests */
    struct list_head mq_list; /* blk-mq requests */
    struct list_head cb_list; /* md requires an unplug callback */
};

rq->wbt_flags:
enum wbt_flags {
    WBT_TRACKED     = 1,    /* write, tracked for throttling */
    WBT_READ        = 2,    /* read */
    WBT_KSWAPD      = 4,    /* write, from kswapd */
    WBT_DISCARD     = 8,    /* discard */

    WBT_NR_BITS     = 4,    /* number of bits */
};


enum elv_merge {
    ELEVATOR_NO_MERGE   = 0,
    ELEVATOR_FRONT_MERGE    = 1,
    ELEVATOR_BACK_MERGE = 2,
    ELEVATOR_DISCARD_MERGE  = 3,
};
```

## submit_bio:
```
    submit_bio(bio)
    bio_has_data(bio)
    generic_make_request(bio)
        generic_make_request_checks(bio)
            trace_block_bio_queue(q, bio);            ---- (TP) block:block_bio_queue  (Q)
        loop(bio) {
            q = bio->bi_disk->queue; // q is "struct request_queue", each device owns one.
            flags = xxxx
            blk_queue_enter(q, flags)
            struct bio_list lower, same
            q->make_request_fn(q, bio); // IMPORTANT
                case1:  blk_mq_make_request(q, bio)
                        blk_queue_bounce(q, &bio)
                        blk_queue_split(q, &bio)
                        bio_integrity_prep(bio)
                        blk_attempt_plug_merge(q, bio, &request_count, &same_queue_rq)
                        blk_mq_sched_bio_merge(q, bio)
                case2:  blk_queue_bio(q, bio)
                        blk_queue_bounce(q, &bio);
                            __blk_queue_bounce;       ---- (TP) block:block_bio_bounce (B)
                        blk_queue_split(q, &bio);
                            bio_chain(split, *bio);
                            trace_block_split;        ---- (TP) block:block_split    (S)
                            generic_make_request(*bio);
                        bio_integrity_prep(bio);
                        blk_queue_nomerges(q);
                        blk_attempt_plug_merge(q, bio, &request_count, NULL);
                        elv_merge(q, &req, bio)
                            case: ELEVATOR_BACK_MERGE:
                                  bio_attempt_back_merge(q, req, bio);
                                  elv_bio_merged(q, req, bio);
                                  attempt_back_merge(q, req);
                                  elv_merged_request(q, req, ELEVATOR_BACK_MERGE);
                            case: ELEVATOR_FRONT_MERGE:
                                  bio_attempt_front_merge(q, req, bio);
                                  elv_bio_merged(q, req, bio);
                                  attempt_front_merge(q, req);
                                  elv_merged_request(q, req, ELEVATOR_FRONT_MERGE);

                        blk_queue_enter_live(q);
                        req = get_request(q, bio->bi_opf, bio, 0);
                            __get_request(rl, op, bio, flags);
                                elv_may_queue(q, op);
                                trace_block_getrq(q, bio, op);         ----(TP) block:block_getrq   (G)
                            trace_block_sleeprq(q, bio, op);           ----(TP) block:block_sleeprq (S)
                        if (IS_ERR(req)) {
                            bio_endio(bio);
                        }
                        blk_init_request_from_bio(req, bio);
                        plug = current->plug;
                        blk_flush_plug_list(plug, false);
                            if (op_is_flush(rq->cmd_flags))
                                __elv_add_request(q, rq, ELEVATOR_INSERT_FLUSH);
                                    race_block_rq_insert(q, rq);       ----(TP) block:block_insert_rq   (I)
                            else
                                __elv_add_request(q, rq, ELEVATOR_INSERT_SORT_MERGE);

                        trace_block_plug(q);                           ----(TP) block:block_plug    (P)
                        list_add_tail(&req->queuelist, &plug->list);
                        blk_account_io_start(req, true);

            blk_queue_exit(q);
                percpu_ref_put(&q->q_usage_counter);
                    percpu_ref_put_many(ref, 1);
        }
```


## blk_fetch_request:
* fetch a request from a request queue

```
<struct req>blk_fetch_request(q)
    rq = blk_peek_request(q);
    blk_start_request(struct request *req)
```

## blk_start_request:
* start request processing on the driver
* @req: request to dequeue

```
rq--rq--rq--rq--rq--rq--rq--rq
    blk_start_request(struct request *req)
        blk_dequeue_request(req)
            list_del_init(&rq->queuelist)
            blk_account_rq(rq);
        blk_add_timer(req);
```

## block_unplug:
```
blk_finish_plug(struct blk_plug *plug)
    blk_flush_plug_list(plug, false);
        queue_unplugged(struct request_queue *q, unsigned int depth, bool from_schedule)
            trace_block_unplug(q, depth, !from_schedule);
```

## elv_add_request:
```
elv_add_request(struct request_queue *q, struct request *rq, int where)
    __elv_add_request(q, rq, where);
        trace_block_rq_insert(q, rq);                   ----  (TP) block:block_insert_rq   (I)
        switch(where): {
            case ELEVATOR_INSERT_REQUEUE:
            case ELEVATOR_INSERT_FRONT:
            case ELEVATOR_INSERT_BACK:
            case ELEVATOR_INSERT_SORT_MERGE:
                elv_attempt_insert_merge(q, rq);
            case ELEVATOR_INSERT_SORT:
            case ELEVATOR_INSERT_FLUSH:
                blk_insert_flush(rq);
        }
```

NOTE:

* q is "struct request_queue", each device owns one, so
  q owns lots of callback functions, such as: "make_request_fn"
* "q->make_request_fn =" will be set in function: blk_queue_make_request

## Multi-queue:   ---- blk_mq_make_request
blk_mq_make_request is initial from scsi...

```
blk_mq_init_queue<struct request_queue>
    blk_alloc_queue_node<struct request_queue>
    blk_mq_init_allocated_queue<struct request_queue>
        blk_mq_make_request(struct request_queue *q, struct bio *bio)
        blk_queue_make_request(q, blk_mq_make_request);  ;Setting callback function: q->make_request_fn = blk_mq_make_request
```


## Init request queue: ---- blk_queue_bio

```
blk_init_queue <struct request_queue>
    blk_init_queue_node <struct request_queue>
        blk_init_allocated_queue(struct request_queue *q)
            blk_queue_make_request(q, blk_queue_bio);
                blk_queue_bio
                    get_request
                        __get_request
```
