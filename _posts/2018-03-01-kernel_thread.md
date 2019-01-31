---
layout: post
title: "In-depth code reserach - task_struct"
author: muahao
tags:
- kernel
- scheduler

---

## process description and struct 
### process struct 
```
Kernel alloc task_struct by slab

struct task_struct  {
	
}

there is a thread_info at x86, it is placed at the end of it's kernel stack to record where is task_struct?

struct thread_info {
	struct task_struct *task;
}

```

We use `current macro` point to current process, but maybe we don't know,  power PC have a special register to record current `task_struct`, because power PC think it's neccesary and worthy to design a special register, but x86 is lack of register, so x86 don't have a special register to point to current `task_struct`

### task list 
There is a list to record all `task_struct`, we know `task_struct` size is a little big about 1.7KB at 32 bit kernel.

### How to set task_struct status?

kernel alway change the task_struct's state.

```
set_task_state(task, state);

set_current_state(state) == set_task_state(current, state);
```


### How to get parent?
```
struct task_struct *my_parent = current->parent;
```

### How to get children?
```
struct task_struct *task;
struct list_head *list;

list_for_each(list, &current->children) {
	task = list_entry(list, struct task_struct, sibling);
	
	
}
```

### How to traverse a task queue(任务队列)?
Well, we should know that task queue is a circle list actually. 
So how to traverse a task queue is easy;

Get the next `task_struct` in the list by a given `task_struct`:

```
list_entry(task->tasks.next, struct task_struct, tasks);

or macro: 
next_task(task);
```

Get the prev `task_struct` in the list by a given `task_struct`:

```
list_entry(task->task.prev, struct task_struct, tasks);

or macro:
prev_task(task);
```

traverse all task in the task queue: (It's a heavy work!)

```
struct task_struct *task;

for_each_process(task) {
	printk("%s [%d]\n", task->comm, task->pid);
}
```



## process create

```
fork(): Copy current process and create a child process.(But not include pid, ppid, and signal related.)
exec(): Load excutive binary in memory space and begin running. 
```
### copy-on-write:
Well, fork() syscall always create a new child process, and then copy all it's resource to child, but maybe child don't need it, maybe child will call exec() syscall soon, if so, the resource copyed is wasteful. 

So, the copy-on-write technich appear. When create a child process, will not copy all resource to child soon, just only share it. If child process execute exec(), ok, it's not neccessary to copy resource to child process. 


### fork

Linux use clone() syscall to come true fork() syscall; 

## thread in linux
thread is 线程
process is 进程

* We should know there is no a special struct to describe thread in kernerl. 
* Actually there is no thread conception in kernel.
* Kernel treat thread just like process.

### Create thread
create thread is likely with create process. 

We already know that fork() syscall is come true by clone() syscall: 

```
clone(CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND, 0);
```
As this way, the thread is created and it share with it's parent for memory address, file resource. 

A common fork() syscall is come true by :


```
fork() = clone(SIGHLD, 0);
```

### Kernel thread

* kernel thread don't have it's own independent memory address. 
* kernel thread's mm pointer point to NULL.
* kernel thread only running in kernel space, never go to user space.
* kernel thread can be sched and 抢占.


#### How to create a kernel thread 
```
struct task_struct *kthread_run(int (*threadfn)(void *data), void *data, const char namefmt[], ...)
```

`kthread_run` macro is come true by `kthread_create()` and `wake_up_proces()`;

```
#define kthread_run(threadfn, data, namefmt, ...)
({
	struct task_struct *k;
	
	k = kthread_create(threadfn, data, namefmt, ##__VA_ARGS__);
	if (!IS_ERR(k))
		wake_up_process(k);
	k;
})
```

When kernel thread start run, will be exit when call `do_exit()` or somewhere call `kthread_stop()`

```
int kthread_stop(struct task_struct *k);
```

## process exit
exit() syscall; 

do_exit()

