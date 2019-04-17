---
layout: post
title: "一个简单内核驱动，通过qemu调试(1)"
author: muahao
excerpt: "一个简单内核驱动，通过qemu调试(1)"
tags:
- driver
---

## 模块
通过在HOST上修改linux kernel源代码，重新编译一个vmlinux，然后，通过qemu根据这个bzImage 启动一个vm，进行调试

```
#cat  drivers/char/test.c
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/sysfs.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/mm_types.h>

#define DRIVER_VERSION "1.0.0"
#define DRIVER_AUTHOR "Ahao Mu"
#define DRIVER_DESC "TEST_MODULE"

static struct proc_dir_entry *pde = NULL;

static int test_open(struct inode *inode, struct file *file)
{
	pr_info("%s (%s) test_open\n", DRIVER_DESC, DRIVER_VERSION);
	return 0;
}

static ssize_t test_read(struct file *file, char __user *buf, size_t length, loff_t *ppos)
{
	pr_info("%s (%s) test_read\n", DRIVER_DESC, DRIVER_VERSION);

	struct vm_area_struct *vma;
	struct dentry *dentry;

	for (vma = current->mm->mmap; vma; vma = vma->vm_next) {
		dentry = (vma->vm_file && vma->vm_file->f_path.dentry ?
				  vma->vm_file->f_path.dentry: NULL);

		pr_info("[%016x - %016x] [%016x %016x] [%s]\n",
				vma->vm_start, vma->vm_end,
				vma->vm_page_prot.pgprot,
				vma->vm_flags,
				dentry ? (char *)dentry->d_name.name : "");
	}

	return 0;
}

static int test_release(struct inode *inode, struct file *file)
{
	pr_info("%s (%s) test_release", DRIVER_DESC, DRIVER_VERSION);
	return 0;
}

static loff_t test_lseek(struct file *file, loff_t loff, int a)
{
	pr_info("%s (%s) test_release", DRIVER_DESC, DRIVER_VERSION);
	return loff;
}

static const struct file_operations test_proc_fops = {
	.owner = THIS_MODULE,
	.open = test_open,
	.read = test_read,
	.llseek = test_lseek,
	.release = test_release,
};

static int __init test_init(void)
{
	pr_info("%s (%s) loaded", DRIVER_DESC, DRIVER_VERSION);
	pde = proc_create("test", 0, NULL, &test_proc_fops);
	if (!pde) {
		pr_warn("%s: Unable to create /proc/test\n", __func__);
		return -ENOMEM;
	}
	return 0;
}

static void __exit test_exit(void)
{
	pr_info("%s (%s) unload", DRIVER_DESC, DRIVER_VERSION);
}

module_init(test_init);
module_exit(test_exit);

MODULE_VERSION(DRIVER_VERSION);
MODULE_LICENSE("GPL V2");
MODULE_AUTHOR(DRIVER_AUTHOR);
MODULE_DESCRIPTION(DRIVER_DESC);
```

```
#vim  drivers/char/Makefile
obj-y				+= test.o
```

## 调试
从HOST上对GUEST(vm) 启动的kernel进行调试

```
#gdb vmlinux
#(gdb) target remote localhost:1234
#(gdb) b drivers/char/test.c:test_read
Breakpoint 1 at 0xffffffff8151cac0: file drivers/char/test.c, line 22.
(gdb)
(gdb) info b
Num     Type           Disp Enb Address            What
1       breakpoint     keep y   0xffffffff8151cac0 in test_read at drivers/char/test.c:22
(gdb)
(gdb) c
Continuing.
[Switching to Thread 1.2]

Thread 2 hit Breakpoint 1, test_read (file=0xffff880468ba4300, buf=0xffff8804688b3000 "", length=4096, ppos=0xffffc90001ddbc90) at drivers/char/test.c:22
22	{
(gdb)
```
