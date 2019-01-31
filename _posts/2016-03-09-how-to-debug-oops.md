---
layout: post
title: "Linux kernel crash/Oops debug skills"
author: muahao
tags:
- kernel
- crash
---

在内核开发的过程中，经常会碰到内核崩溃，比如空指针异常，内存访问越界。通常我们只能靠崩溃之后打印出的异常调用栈信息来定位crash的位置和原因。总结下分析的方法和步骤。

通常oops发生之后，会在串口控制台或者dmesg日志输出看到如下的log，以某arm下linux内核的崩溃为例，

```
<2>[515753.310000] kernel BUG at net/core/skbuff.c:1846!
<1>[515753.310000] Unable to handle kernel NULL pointer dereference at virtual address 00000000
<1>[515753.320000] pgd = c0004000
<1>[515753.320000] [00000000] *pgd=00000000
<0>[515753.330000] Internal error: Oops: 817 [#1] PREEMPT SMP
<0>[515753.330000] last sysfs file: /sys/class/net/eth0.2/speed
<4>[515753.330000] module:  http_timeout     bf098000    4142
...
<4>[515753.330000] CPU: 0    Tainted: P             (2.6.36 #2)
<4>[515753.330000] PC is at __bug+0x20/0x28
<4>[515753.330000] LR is at __bug+0x1c/0x28
<4>[515753.330000] pc : [<c01472d0>]    lr : [<c01472cc>]    psr: 60000113
<4>[515753.330000] sp : c0593e20  ip : c0593d70  fp : cf1b5ba0
<4>[515753.330000] r10: 00000014  r9 : 4adec78d  r8 : 00000006
<4>[515753.330000] r7 : 00000000  r6 : 0000003a  r5 : 0000003a  r4 : 00000060
<4>[515753.330000] r3 : 00000000  r2 : 00000204  r1 : 00000001  r0 : 0000003c
<4>[515753.330000] Flags: nZCv  IRQs on  FIQs on  Mode SVC_32  ISA ARM  Segment kernel
<4>[515753.330000] Control: 10c53c7d  Table: 4fb5004a  DAC: 00000017
<0>[515753.330000] Process swapper (pid: 0, stack limit = 0xc0592270)
<0>[515753.330000] Stack: (0xc0593e20 to 0xc0594000)
<0>[515753.330000] 3e20: ce2ce900 c0543cf4 00000000 ceb4c400 000010cc c8f9b5d8 00000000 00000000
<0>[515753.330000] 3e40: 00000001 cd469200 c8f9b5d8 00000000 ce2ce8bc 00000006 00000026 00000010
...
<4>[515753.330000] [<c01472d0>] (PC is at __bug+0x20/0x28)
<4>[515753.330000] [<c01472d0>] (__bug+0x20/0x28) from [<c0543cf4>] (skb_checksum+0x3f8/0x400)
<4>[515753.330000] [<c0543cf4>] (skb_checksum+0x3f8/0x400) from [<bf11a8f8>] (et_isr+0x2b4/0x3dc [et])
<4>[515753.330000] [<bf11a8f8>] (et_isr+0x2b4/0x3dc [et]) from [<bf11aa44>] (et_txq_work+0x24/0x54 [et])
<4>[515753.330000] [<bf11aa44>] (et_txq_work+0x24/0x54 [et]) from [<bf11aa88>] (et_tx_tasklet+0x14/0x298 [et])
<4>[515753.330000] [<bf11aa88>] (et_tx_tasklet+0x14/0x298 [et]) from [<c0171510>] (tasklet_action+0x12c/0x174)
<4>[515753.330000] [<c0171510>] (tasklet_action+0x12c/0x174) from [<c05502b4>] (__do_softirq+0xfc/0x1a4)
<4>[515753.330000] [<c05502b4>] (__do_softirq+0xfc/0x1a4) from [<c0171c98>] (irq_exit+0x60/0x64)
<4>[515753.330000] [<c0171c98>] (irq_exit+0x60/0x64) from [<c01431fc>] (do_local_timer+0x60/0x74)
<4>[515753.330000] [<c01431fc>] (do_local_timer+0x60/0x74) from [<c054f900>] (__irq_svc+0x60/0x10c)
<4>[515753.330000] Exception stack(0xc0593f68 to 0xc0593fb0)
```

在这里，我们着重关注下面几点：

Oops信息 `kernel BUG at net/core/skbuff.c:1846! Unable to handle kernel NULL pointer dereference at virtual address 00000000` ， 这里能够简要的告诉是什么问题触发了oops,如果是由代码直接调用BUG()/BUG_ON()一类的，还能给出源代码中触发的行号。

寄存器PC/LR的值 PC `is at __bug+0x20/0x28 LR is at __bug+0x1c/0x28 `, 这里PC是发送oops的指令， 可以通过LR找到函数的调用者

CPU编号和CPU寄存器的值 `sp ip fp r0~r10 `，

oops时，应用层的`Process Process swapper (pid: 0, stack limit = 0xc0592270)` ， 如果crash发生在内核调用上下文，这个可以用来定位对应的用户态进程

最重要的是调用栈，可以通过调用栈来分析错误位置

这里需要说明一点， `skb_checksum+0x3f8/0x400 `，在反汇编后，可以通过找到skb_checksum函数入口地址偏移0x3f8来精确定位执行点

在需要精确定位出错位置的时候，我们就需要用到反汇编工具objdump了。下面就是一个示例，

```
    objdump -D -S xxx.o > xxx.txt
```

举个例子，比如我们需要寻找栈 `(et_isr+0x2b4/0x3dc [et]) from [<bf11aa44>] (et_txq_work+0x24/0x54 [et]) `，这里我们可以知道这个函数是在 [et] 这个obj文件中，那么我们可以直接去找 et.o ，然后反汇编 `objdump -D -S et.o > et.txt` , 然后et.txt中就是反汇编后的指令。当然，单看汇编指令会非常让人头疼，我们需要反汇编指令和源码的一一对应才好分析问题。这就需要我们在编译compile的时候加上 -g 参数，把编译过程中的symbol和调试信息一并加入到最后obj文件中，这样objdump反汇编之后的文件中就包含嵌入的源码文件了。

对于内核编译来讲，就是需要在内核编译的根目录下，修改Makefile中 KBUILD_CFLAGS , 加上 -g 编译选项。

```
    KBUILD_CFLAGS   := -g -Wall -Wundef -Wstrict-prototypes -Wno-trigraphs \                       
               -fno-strict-aliasing -fno-common \
               -Werror-implicit-function-declaration \
               -Wno-format-security \
               -fno-delete-null-pointer-checks -Wno-implicit-function-declaration \
               -Wno-unused-but-set-variable \
               -Wno-unused-local-typedefs
```

下面是一份反编译完成后的文件的部分截取。我们可以看到，这里0x1f0是` <et_isr>` 这个函数的入口entry，c的源代码是在前面，后面跟的汇编代码是对应的反汇编指令

```
f0 <et_isr>:
et_isr(int irq, void *dev_id)
#else
static irqreturn_t BCMFASTPATH
et_isr(int irq, void *dev_id, struct pt_regs *ptregs)
#endif
{
f0:   e92d40f8    push    {r3, r4, r5, r6, r7, lr}
f4:   e1a04001    mov r4, r1
    struct chops *chops;
    void *ch;
    uint events = 0;

    et = (et_info_t *)dev_id;
    chops = et->etc->chops;
f8:   e5913000    ldr r3, [r1]
    ch = et->etc->ch;

    /* guard against shared interrupts */
    if (!et->etc->up)
fc:   e5d32028    ldrb    r2, [r3, #40]   ; 0x28
    struct chops *chops;
    void *ch;
    uint events = 0;

    et = (et_info_t *)dev_id;
    chops = et->etc->chops;
:   e5936078    ldr r6, [r3, #120]  ; 0x78
    ch = et->etc->ch;
:   e593507c    ldr r5, [r3, #124]  ; 0x7c

    /* guard against shared interrupts */
    if (!et->etc->up)
:   e3520000    cmp r2, #0
c:   1a000001    bne 218 <et_isr+0x28>
:   e1a00002    mov r0, r2
:   e8bd80f8    pop {r3, r4, r5, r6, r7, pc}
        goto done;

    /* get interrupt condition bits */
    events = (*chops->getintrevents)(ch, TRUE);
:   e5963028    ldr r3, [r6, #40]   ; 0x28
c:   e1a00005    mov r0, r5
:   e3a01001    mov r1, #1
:   e12fff33    blx r3
:   e1a07000    mov r7, r0

    /* not for us */
    if (!(events & INTR_NEW))
c:   e2100010    ands    r0, r0, #16
:   08bd80f8    popeq   {r3, r4, r5, r6, r7, pc}

    ET_TRACE(("et%d: et_isr: events 0x%x\n", et->etc->unit, events));
    ET_LOG("et%d: et_isr: events 0x%x", et->etc->unit, events);

    /* disable interrupts */
    (*chops->intrsoff)(ch);
:   e5963038    ldr r3, [r6, #56]   ; 0x38
:   e1a00005    mov r0, r5
c:   e12fff33    blx r3
        (*chops->intrson)(ch);
    }
```


在objdump反汇编出指令之后，我们可以根据调用栈上的入口偏移来找到对应的精确调用点。例如， `(et_isr+0x2b4/0x3dc [et]) from [<bf11aa44>] (et_txq_work+0x24/0x54 [et])` ， 我们可以知道调用点在` et_isr`入口位置+0x2b4偏移 ，而刚才我们看到 `et_isr`的入口位置是0x1f0 ,那就是说在 `0x1f0+0x2b4=0x4a4 `偏移位置。我们来看看，如下指令 `4a4: e585007c str r0, [r5, #124] ; 0x7c `，其对应的源代码就是上面那一段c代码， `skb->csum = skb_checksum(skb, thoff, skb->len - thoff, 0); `。而我们也知道，下一个调用函数的确是 `skb_checksum` , 说明精确的调用指令是准确的。

```
        ASSERT((prot == IP_PROT_TCP) || (prot == IP_PROT_UDP));
        check = (uint16 *)(th + ((prot == IP_PROT_UDP) ?
c:   e3580011    cmp r8, #17
:   13a0a010    movne   sl, #16
:   03a0a006    moveq   sl, #6
            offsetof(struct udphdr, check) : offsetof(struct tcphdr, check)));
        *check = 0;
:   e18720ba    strh    r2, [r7, sl]
    thoff = (th - skb->data);
    if (eth_type == HTON16(ETHER_TYPE_IP)) {
        struct iphdr *ih = ip_hdr(skb);
        prot = ih->protocol;
        ASSERT((prot == IP_PROT_TCP) || (prot == IP_PROT_UDP));
        check = (uint16 *)(th + ((prot == IP_PROT_UDP) ?
c:   e087200a    add r2, r7, sl
:   e58d2014    str r2, [sp, #20]
            offsetof(struct udphdr, check) : offsetof(struct tcphdr, check)));
        *check = 0;
        ET_TRACE(("et%d: skb_checksum: \n", et->etc->unit));
        skb->csum = skb_checksum(skb, thoff, skb->len - thoff, 0);
:   e5952070    ldr r2, [r5, #112]  ; 0x70
:   e58dc008    str ip, [sp, #8]
c:   e0612002    rsb r2, r1, r2
a0:   ebfffffe    bl  0 <skb_checksum>
a4:   e585007c    str r0, [r5, #124]  ; 0x7c
        *check = csum_tcpudp_magic(ih->saddr, ih->daddr,
a8:   e5953070    ldr r3, [r5, #112]  ; 0x70

static inline __wsum
csum_tcpudp_nofold(__be32 saddr, __be32 daddr, unsigned short len,
           unsigned short proto, __wsum sum)
{     
    __asm__(
ac:   e59dc008    ldr ip, [sp, #8]
```

有几点比较geek的地方需要注意：

函数调用栈的调用不一定准确（不知道why？可能因为调用过程是通过LR来反推到的，LR在执行过程中有可能被修改？），但是有一点可以确认，调用的点是准确的，也就是说调用函数不一定准，但是调用函数+偏移是能够找到准确的调入指令
inline的函数以及被优化的函数可能不会出现在调用栈上，在编译的时候因为优化的需要，会就地展开代码，这样就不会在这里有调用栈帧（stack frame）存在了

## REF

[https://www.ibm.com/developerworks/cn/linux/l-cn-kdump4/index.html?ca=drs](https://www.ibm.com/developerworks/cn/linux/l-cn-kdump4/index.html?ca=drs)
