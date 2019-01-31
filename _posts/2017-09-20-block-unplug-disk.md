---
layout: post
title: "如何优雅的拔掉 /dev/sdl"
author: muahao
tags:
- block
---

如何优雅的拔掉 /dev/sdl？

```
#lsscsi
[6:0:0:0]    disk    ATA      ST2000NM0011     SN02  /dev/sda
[6:0:1:0]    disk    ATA      ST2000NM0011     SN02  /dev/sdb
[6:0:2:0]    disk    ATA      ST2000NM0011     SN02  /dev/sdc
[6:0:3:0]    disk    ATA      ST2000NM0011     SN02  /dev/sdd
[6:0:4:0]    disk    ATA      ST2000NM0011     SN02  /dev/sde
[6:0:5:0]    disk    ATA      ST2000NM0011     SN02  /dev/sdf
[6:0:6:0]    disk    ATA      ST2000NM0011     SN02  /dev/sdg
[6:0:7:0]    disk    ATA      ST2000NM0011     SN02  /dev/sdh
[6:0:8:0]    disk    ATA      ST2000NM0011     SN02  /dev/sdi
[6:0:9:0]    disk    ATA      ST2000NM0011     SN02  /dev/sdj
[6:0:10:0]   disk    ATA      ST2000NM0011     SN02  /dev/sdk
[6:0:11:0]   disk    ATA      ST2000NM0011     SN02  /dev/sdl
[6:0:12:0]   enclosu SAS/SATA  Expander        RevA  -


#echo "scsi remove-single-device 6 0 11 0" > /proc/scsi/scsi

然后插上：

#echo "scsi add-single-device 6 0 11 0" > /proc/scsi/scsi
```
