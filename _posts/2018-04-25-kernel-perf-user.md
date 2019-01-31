---
layout: post
title: "In-depth code research - perf"
author: muahao
excerpt: In-depth code research - perf
tags:
- kernel
- perf
---
# perf user源码分析
## 前言
简单来说，perf是一种性能监测工具，它首先对通用处理器提供的performance counter进行编程，设定计数器阈值和事件，然后性能计数器就会在设定事件发生时递增计数器，直至这个计数器的计数值达到阈值，在不同的结构中对于计数器数值的提取有不同的方式，例如MIPS上会注册一个硬件中断，这样在计数器溢出时触发一个硬件中断，在中断处理函数中记录数值，x86中则是利用通知链机制，将溢出处理函数注册到die_chain通知链上，它会利用任何一个硬件中断发生的时机，检测性能计数器是否溢出，是则记录这个数值，这种实现方式就避免了单独为性能计数器溢出注册一个硬件中断。

perf源码分为用户层和内核层，用户层代码为用户提供命令行指定事件与采样方式，perf的一大特点就体现在丰富的用户层工具，可以说，内核部分代码只是为perf提供采样引擎，用户层才是perf的精华。用户层代码位于src/tools/perf目录下，c代码有13000行左右，此外还有大量的脚本程序。内核层代码分为结构无关代码（位于src/kernel/core/目录），和结构相关代码（位于src/arch/x86/cpu/**）。

这里先列个框架：首先从系统启动初始化开始，perf-init的相关工作，之后介绍用户层指定事件，通过系统调用转入内核，执行采样，采样数据通过内存映射返回给用户层，用户层工具进行上层分析并显示

## 源码分析(一)——perf record
### perf's main entry
```
tools/perf/perf.c

static struct cmd_struct commands[] = {
    { "buildid-cache", cmd_buildid_cache, 0 },
    { "buildid-list", cmd_buildid_list, 0 },
    { "diff",   cmd_diff,   0 },
    { "evlist", cmd_evlist, 0 },
    { "help",   cmd_help,   0 },
    { "list",   cmd_list,   0 },
    { "record", cmd_record, 0 },
    { "report", cmd_report, 0 },
    { "bench",  cmd_bench,  0 },
    { "stat",   cmd_stat,   0 },
    { "timechart",  cmd_timechart,  0 },
    { "top",    cmd_top,    0 },
    { "annotate",   cmd_annotate,   0 },
    { "version",    cmd_version,    0 },
    { "script", cmd_script, 0 },
    { "sched",  cmd_sched,  0 },
#ifdef HAVE_LIBELF_SUPPORT
    { "probe",  cmd_probe,  0 },
#endif
    { "kmem",   cmd_kmem,   0 },
    { "lock",   cmd_lock,   0 },
    { "kvm",    cmd_kvm,    0 },
    { "test",   cmd_test,   0 },
#ifdef HAVE_LIBAUDIT_SUPPORT
    { "trace",  cmd_trace,  0 },
#endif
    { "inject", cmd_inject, 0 },
    { "mem",    cmd_mem,    0 },
    { "data",   cmd_data,   0 },
};
```


### perf record's CALL CHAIN:


```
cmd_record
	;; new a struct "record" rec, and a struct "evlist" in rec->evlist;
	perf_evlist__new
	perf_config
	__cmd_record(&record, argc, argv); // fill out "struct record"
		perf_session__new(file, false, tool); // New a sesssion for this rec, rec->session, attention: file is "struct perf_data_file *file",  &rec->file;
			machines__init(&session->machines);
			ordered_events__init(&session->ordered_events, ordered_events__deliver_event);
			perf_data_file__open(file)
				check_pipe(file)
				file->path = "perf.data" // If not specified name, fill out file->path
				open_file(file);
					fd = perf_data_file__is_read(file) ? open_file_read(file) : open_file_write(file);
					file->fd = fd;
			perf_session__create_kernel_maps(session) //
		fd = perf_data_file__fd(file); // Get rec's fd, rec->file->fd
		record__init_features(rec);
			perf_header__set_feat // Fill out session's header of this rec, rec->session->header
		record__open(rec)
			perf_evlist__config(evlist, opts); // perf_evlist
				perf_evsel__config(evsel, opts); // perf_evsel
		perf_header__clear_feat
		perf_header__write_pipe / perf_session__write_header
		perf_event__synthesize_kernel_mmap(tool, process_synthesized_event, machine);
		perf_event__synthesize_modules(tool, process_synthesized_event, machine);
		machines__process_guests(&session->machines,perf_event__synthesize_guest_os, tool);
		__machine__synthesize_threads(machine, tool, &opts->target, rec->evlist->threads,process_synthesized_event, opts->sample_address);


```



```
tools/perf/builtin-record.c

int cmd_record(int argc, const char **argv, const char *prefix __maybe_unused)
{
    int err = -ENOMEM;
    struct record *rec = &record;
    char errbuf[BUFSIZ];

    rec->evlist = perf_evlist__new();
    if (rec->evlist == NULL)
        return -ENOMEM;

    perf_config(perf_record_config, rec);  // 解析, tools/perf/util/config.c

    argc = parse_options(argc, argv, record_options, record_usage,
                PARSE_OPT_STOP_AT_NON_OPTION);
    if (!argc && target__none(&rec->opts.target))
        usage_with_options(record_usage, record_options);

    if (nr_cgroups && !rec->opts.target.system_wide) {
        ui__error("cgroup monitoring only available in"
              " system-wide mode\n");
        usage_with_options(record_usage, record_options);
    }
}

```
```
tools/perf/util/parse-events.c

setup_events // tools/perf/builtin-stat.c
	parse_events // tools/perf/util/parse-events.c

parse_events  // tools/perf/util/parse-events.c

int parse_events(struct perf_evlist *evlist, const char *str)
{
    struct parse_events_evlist data = {
        .list = LIST_HEAD_INIT(data.list),
        .idx  = evlist->nr_entries,
    };
    int ret;

    ret = parse_events__scanner(str, &data, PE_START_EVENTS);
    perf_pmu__parse_cleanup();
    if (!ret) {
        int entries = data.idx - evlist->nr_entries;
        perf_evlist__splice_list_tail(evlist, &data.list, entries);
        evlist->nr_groups += data.nr_groups;
        return 0;
    }

    /*
     * There are 2 users - builtin-record and builtin-test objects.
     * Both call perf_evlist__delete in case of error, so we dont
     * need to bother.
     */
    return ret;
}
```
### struct introduction

```
tools/perf/util/target.h

struct target {
    const char   *pid;
    const char   *tid;
    const char   *cpu_list;
    const char   *uid_str;
    uid_t        uid;
    bool         system_wide;
    bool         uses_mmap;
    bool         default_per_cpu;
    bool         per_thread;
};
===

tools/perf/util/data.h

struct perf_data_file {
    const char      *path;
    int          fd;
    bool             is_pipe;
    bool             force;
    unsigned long        size;
    enum perf_data_mode  mode;
};

===

tools/perf/util/session.h

struct perf_session {
    struct perf_header  header;
    struct machines     machines;
    struct perf_evlist  *evlist;
    struct trace_event  tevent;
    bool            repipe;
    bool            one_mmap;
    void            *one_mmap_addr;
    u64         one_mmap_offset;
    struct ordered_events   ordered_events;
    struct perf_data_file   *file;
    struct perf_tool    *tool;
};

===

tools/perf/util/evlist.h

struct perf_evlist {
    struct list_head entries;
    struct hlist_head heads[PERF_EVLIST__HLIST_SIZE];
    int      nr_entries;
    int      nr_groups;
    int      nr_mmaps;
    size_t       mmap_len;
    int      id_pos;
    int      is_pos;
    u64      combined_sample_type;
    struct {
        int cork_fd;
        pid_t   pid;
    } workload;
    bool         overwrite;
    struct fdarray   pollfd;
    struct perf_mmap *mmap;
    struct thread_map *threads; // threads
    struct cpu_map    *cpus;   // cpus
    struct perf_evsel *selected;
    struct events_stats stats;
};

===

/** struct perf_evsel - event selector **/

Each event passed from user mapping one perf_evsel struct.

struct perf_evsel {
    struct list_head    node;
    struct perf_event_attr  attr;
    char            *filter;
    struct xyarray      *fd;
    struct xyarray      *sample_id;
    u64         *id;
    struct perf_counts  *counts;
    struct perf_counts  *prev_raw_counts;
    int         idx;
    u32         ids;
    char            *name;
    double          scale;
    const char      *unit;
    bool            snapshot;
    struct event_format *tp_format;
    ...
    ...
    struct perf_evsel   *leader;
}

===

tools/perf/builtin-record.c

struct record {
    struct perf_tool    tool;
    struct record_opts  opts;
    u64         bytes_written;
    struct perf_data_file   file;
    struct perf_evlist  *evlist;
    struct perf_session *session;
    const char      *progname;
    int         realtime_prio;
    bool            no_buildid;
    bool            no_buildid_cache;
    long            samples;
};

===
Here is important, perf_stat is an array include three "struct stats" in "perf_stat",
and will init perf_stat:
    for (i = 0; i < 3; i++)
        init_stats(&ps->res_stats[i]);


struct perf_stat {
    struct stats      res_stats[3];
};

tools/perf/util/stat.h

struct stats
{
    double n, mean, M2;
    u64 max, min;
};

====
tools/perf/util/evsel.h

struct perf_counts_values {
    union {
        struct {
            u64 val;
            u64 ena;
            u64 run;
        };
        u64 values[3];
    };
};

struct perf_counts {
    s8            scaled;
    struct perf_counts_values aggr;
    struct perf_counts_values cpu[];
};



```

## 源码分析(二)——perf stat


### perf stat's CALL CHAIN

```
CALL CHAIN:
commands // tools/perf/perf.c
	cmd_stat // tools/perf/builtin-stat.c
		parse_events_option // If perf stat -e xxx, specified event name, will check this event name
			parse_events
 				parse_events__scanner // check events
 					parse_events_lex_init_extra
 					parse_events__scan_string
 					parse_events_parse
 					parse_events__flush_buffer
 					parse_events__delete_buffer
 					parse_events_lex_destroy
				perf_pmu__parse_cleanup:
		perf_evlist__new();
			perf_evlist__init(struct perf_evlist *evlist, struct cpu_map *cpus, struct thread_map *threads) // evlist->cpus, evlist->threads
				perf_evlist__set_maps ///
		parse_options
		parse_options_usage
		add_default_attributes()
		target__validate(&target);

		// 1. 根据target->pid 创建pid thread_maps存储指定pid的所有tid, thread_maps->nr 数量， thread_maps->map[] 包含所有的tid
		perf_evlist__create_maps(evsel_list, &target) // fill out evlist->threads(thread_map)
			evlist->threads = thread_map__new_str(target->pid, target->tid, target->uid); // evlist->threads
			// 检查thread_map可以使用函数: size_t thread_map__fprintf(struct thread_map *threads, FILE *fp)
			evlist->threads(thread_map) = [tid,tid,tid,tid,...]
			target__uses_dummy_map(target)
				evlist->cpus = cpu_map__dummy_new() // evlist->cpus
				evlist->cpus = cpu_map__new(target->cpu_list)

		// 1. 每个event,分配并且初始化 struct perf_stat, evsel->priv
		// 2. 每个event,分配ncpu*(struct perf_counts_values), evsel->counts
		perf_evlist__alloc_stats(evsel_list, interval)  // Traverse all evsel
			evlist__for_each(evlist, evsel) {
				perf_evsel__alloc_stat_priv(evsel) // Alloc memory for each evsel->priv = zalloc(sizeof(struct perf_stat));
					perf_evsel__reset_stat_priv(evsel)
						init_stats // Fill out "struct perf_stat", perf_stat
									  include 3 elements of "struct stats{}",
									  defined in file: tools/perf/util/stat.h
				perf_evsel__alloc_counts(evsel, perf_evsel__nr_cpus(evsel)) //  Alloc evsel->counts
					perf_evsel__nr_cpus // 1. <struct cpu_map> return (evsel->cpus && !target.cpu_list) ? evsel->cpus : evsel_list->cpus;
				// 数据存储在: evsel->prev_raw_counts
				// 结构体: struct perf_counts_value
				// evsel->prev_raw_counts = Alloc sizeof(*evsel->counts) + (perf_evsel__nr_cpus(evsel) * sizeof(struct perf_counts_values));
				alloc_raw && perf_evsel__alloc_prev_raw_counts(evsel)
			}

		perf_stat_init_aggr_mode()
			case AGGR_SOCKET: // socket维度创建map
				cpu_map__build_socket_map
					cpu_map__build_map(cpus, sockp, cpu_map__get_socket);
					cpu_map__get_socket
			case AGGR_CORE: // cpu维度创建map
				cpu_map__build_core_map
					cpu_map__build_map(cpus, corep, cpu_map__get_core);
					cpu_map__get_core
						cpu_map__get_socket

		run_perf_stat(argc, argv);
			__run_perf_stat(argc, argv);
				perf_evlist__prepare_workload(evsel_list, &target, argv, false, workload_exec_failed_signal)
				perf_evlist__set_leader(evsel_list); // evlist->nr_groups  = 1 or 0 ? decide by evlist->nr_entries > 1 or not
					__perf_evlist__set_leader(&evlist->entries);
					evlist__for_each(evsel_list, evsel) {  // Traverse all evsel
						create_perf_stat_counter(evsel)
							struct perf_event_attr *attr = &evsel->attr;
							attr->xxx  = xxx
							perf_evsel__open_per_cpu(evsel, perf_evsel__cpus(evsel)
							perf_evsel__is_group_leader(evsel)
							perf_evsel__open_per_thread(evsel, evsel_list->threads)
								// important: __perf_evsel__open(struct perf_evsel *evsel, struct cpu_map *cpus, struct thread_map *threads)
								__perf_evsel__open(evsel, &empty_cpu_map.map, threads)
									// perf_evsel__alloc_fd(struct perf_evsel *evsel, int ncpus, int nthreads), if system_wide: nthreads = 1
									// 给每一个evsel->fd 分配内存,大小是一个二维数组: x * y * int = cpus * threads * int
									perf_evsel__alloc_fd(evsel, cpus->nr, nthreads)
										// evsel->fd 是 struct xyarray,仅仅分配内存
										evsel->fd = xyarray__new(ncpus, nthreads, sizeof(int));
									for (cpu = 0; cpu < cpus->nr; cpu++) {
										 for (thread = 0; thread < nthreads; thread++) {
										 	group_fd = get_group_fd(evsel, cpu, thread);
										 	sys_perf_event_open(&evsel->attr, pid, cpus->map[cpu], group_fd, flags);
										 }
									}
					}
					perf_evlist__apply_filters(evsel_list, &counter)
					evlist__for_each(evlist, evsel) {
						perf_evsel__set_filter(evsel, ncpus, nthreads, evsel->filter);
					}
					t0 = rdclock();
					clock_gettime(CLOCK_MONOTONIC, &ref_time);
					if (forks) {
						perf_evlist__start_workload(evsel_list);
						handle_initial_delay();
						if (interval) {
							print_interval();
						}
					} else {
						handle_initial_delay();
						print_interval();
					}
					t1 = rdclock();

					update_stats(&walltime_nsecs_stats, t1 - t0);

					// 开始为每个evsel读
					if (aggr_mode == AGGR_GLOBAL) {
						evlist__for_each(evsel_list, counter) {
							// 读到struct: "struct perf_counts_values", 保存在evsel的 &counter->counts->aggr , （这里evsel 就是counter）
							// 还有“struct perf_stat” ， counter->priv
							read_counter_aggr(counter);
								aggr->val = aggr->ena = aggr->run = 0; // 这里， 把 perf_counts_values aggr 全部初始化为0
								read_counter(counter)  // 如何读此event？遍历每个thread和cpu
									int nthreads = thread_map__nr(evsel_list->threads);
									int ncpus = perf_evsel__nr_cpus(counter);
									int cpu, thread;
									for (thread = 0; thread < nthreads; thread++) {
										for (cpu = 0; cpu < ncpus; cpu++) {
											// pocess + cpu 二维数组方式读, 读到 "struct  perf_counts_values count"
											process_per_cpu(struct perf_evsel *evsel, int cpu, int thread))
												perf_evsel__read_cb(evsel, cpu, thread, &count)
													memset(count, 0, sizeof(*count));
													FD(evsel, cpu, thread)
													readn(FD(evsel, cpu, thread), count, sizeof(*count))
														ion(true, fd, buf, n);
															read(fd, buf, left)

												read_cb(evsel, cpu, thread, tmp);
													switch (aggr_mode) {
														case AGGR_CORE:
														case AGGR_SOCKET:
														case AGGR_NONE:
														perf_evsel__compute_deltas(evsel, cpu, count);
														perf_counts_values__scale(count, scale, NULL);
														update_shadow_stats(evsel, count->values, cpu);

													}
										}
									}
							perf_evsel__close_fd(counter, perf_evsel__nr_cpus(counter), thread_map__nr(evsel_list->threads));
						}
					} else {
						evlist__for_each(evsel_list, counter) {
							read_counter(counter);
							perf_evsel__close_fd(counter, perf_evsel__nr_cpus(counter), 1);
						}
					}

		print_stat
			switch (aggr_mode) {
				case AGGR_SOCKET:
					print_aggr // AGGR_CORE AGGR_SOCKET
				case AGGR_GLOBAL:
					evlist__for_each(evsel_list, counter)
						print_counter_aggr(evsel, NULL); // AGGR_GLOBAL
				case AGGR_NONE:
					evlist__for_each(evsel_list, counter)
						print_counter(evsel, NULL) // AGGR_NONE
			}


```

```
tools/perf/util/evsel.h

struct perf_evsel {

}

```
