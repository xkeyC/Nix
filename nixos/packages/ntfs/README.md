# ntfs 驱动补丁

内核 7.1 起自带的新 ntfs 驱动（Namjae Jeon）的补丁，由 `nixos/storage.nix` 按文件名顺序全部加到
`boot.kernelPatches`。基于 7.3.1，按顺序全部能干净打上（无 fuzz），`fs/ntfs` 单独编译通过，没有警告
（2026-11-07 验证，含 0040）。

## 组成

- `0001`：上游 8deea344965f 移植到 7.3 的版本（7.3 的 inode.c 缺 `ntfs_non_resident_sizes_inconsistent()` 上下文）。
  7.3 把稀疏文件的后续段（扩展 MFT 记录里 lowest_vcn ≠ 0 的 $DATA）误判为损坏：只有第一段带
  compressed_size 字段，校验却要求每一段都有。Steam、网盘下载器在 Windows 下创建的都是稀疏文件，
  读碎片多的大文件时报 “Corrupt 0x80 attribute”，整块盘被重新挂载为只读。
- `0002`–`0038`：v7.3 → v7.4-rc1 之间所有带 `Cc: stable` 的 `fs/ntfs` 修复（37 个），上游原样，按上游提交顺序。
  它们彼此之间有上下文依赖，顺序不能打乱；不需要额外的非 stable 提交。其中：
  - `7823d72305f0`（trigger page_mkwrite for native 4Kn size extension）顺带修了 `ntfs_fallocate()`
    在拿 inode_lock 之前读 i_size 的竞态：期间另一个线程把文件写长，收尾的 `truncate_pagecache()` 按旧大小
    把这次写入还没落盘的脏页丢掉，那段数据读出来全是 0，没有任何报错。并发“从文件末尾写入”+“预分配”就会
    触发，放在 ntfs 上的 qcow2 虚拟盘 2026-11-04 实测丢过数据。
- `0039`：本地补丁。进程等待目录或 inode 读取时被杀（kill、Ctrl+C、程序退出），读取返回 -EINTR，驱动把它当
  卷错误（日志 “error code -4” 或 “Failed to read full index block”），整块盘变只读。
- `0040`：本地补丁。元数据更新路径上的读取被致命信号打断（返回 -EINTR）时，更新停在一半：unlink() 释放簇和
  MFT 记录、删除目录项时改目录索引、分配簇或 MFT 记录。日志 “Failed to map first page (error -4)”、
  “Leaving inconsistent metadata”、“ntfs_index_remove(): Delete failed”、“ntfs_cluster_alloc(): ... (error -4)”，
  卷变只读，磁盘上留下没释放的簇、没目录项的 MFT 记录或坏掉的目录索引。2026-11-07 关机时 QQ 删 SQLite -wal 就是这样。
  补丁加了 `ntfs_read_metadata_folio()`：-EINTR 时不可打断地等已经发出的读取完成，用于所有元数据更新路径上的读取；
  查找和挂载时的读取不变。上游提交在 xkeyC/linux-ntfs 的 fix-eintr-metadata-update 分支。
  验证（QEMU，读取限速 40 IOPS，drop_caches 后中途 kill）：删分散在不同 $Bitmap 页的小文件、删跨 4 个 $Bitmap 页的
  大文件、在 4000 个长文件名的目录里删文件、fallocate、dd conv=fsync。不带 0040 时每个场景都会变只读，删文件的场景
  ntfsck 报 $Bitmap、MFT 和索引损坏（7.3.1 + 0001–0039 删目录项第 2 次就坏了整个目录索引，ntfsck 报 4001 个错误）；带上后每个场景
  20 次都不变只读、ntfsck 干净。在 ntfs-next（KASAN + lockdep）和 7.3.1 上都验证过；ntfs-next 上另外验证了读取被打断后又失败
  （dm-delay + fail_make_request）时返回 -EIO，进程正常退出。没能触发的：在大目录里建文件（kill 都落在查找阶段）。

## 什么时候删

- 内核升级后先看哪些已经包含：在新内核源码上对每个补丁跑 `patch -p1 -R --dry-run`，能反向打上的就是已包含，删掉。
  只删除代码的补丁反向测试可能误判，以源码为准。
- 7.3.y 稳定版会陆续带上 `0002`–`0038`；升到 7.4 后 `0001`–`0038` 都应该已经包含。`0039`、`0040` 要等上游修复。
- 剩下的补丁换到新内核上若有冲突，按上游提交重新移植，保持文件名顺序。

## 清单

| 序号 | 来源 | 标题 |
|---|---|---|
| `0001` | [8deea344965f](https://github.com/torvalds/linux/commit/8deea344965f)，移植到 7.3 | ntfs: only require compressed size on first extent |
| `0002` | [50ed298b6a4b](https://github.com/torvalds/linux/commit/50ed298b6a4b) | ntfs: read MFT writeback bounds under size_lock |
| `0003` | [dfe7ed335b68](https://github.com/torvalds/linux/commit/dfe7ed335b68) | ntfs: validate the MFT I/O geometry |
| `0004` | [b9fa884a3987](https://github.com/torvalds/linux/commit/b9fa884a3987) | ntfs: write MFT mirror data in mapped I/O units |
| `0005` | [ec0a5dd2e385](https://github.com/torvalds/linux/commit/ec0a5dd2e385) | ntfs: serialize raw MFT updates against folio writeback |
| `0006` | [4576ffbded9a](https://github.com/torvalds/linux/commit/4576ffbded9a) | ntfs: track direct MFT writes until BIO completion |
| `0007` | [1df655bcddc2](https://github.com/torvalds/linux/commit/1df655bcddc2) | ntfs: write MFT folios through mapped I/O units |
| `0008` | [4437d9d78718](https://github.com/torvalds/linux/commit/4437d9d78718) | ntfs: write MFT records through containing I/O units |
| `0009` | [43e2fff9f4ec](https://github.com/torvalds/linux/commit/43e2fff9f4ec) | ntfs: use sync flag for direct MFT writes |
| `0010` | [7823d72305f0](https://github.com/torvalds/linux/commit/7823d72305f0) | ntfs: trigger page_mkwrite for native 4Kn size extension |
| `0011` | [418452b43d72](https://github.com/torvalds/linux/commit/418452b43d72) | ntfs: wait for attribute folio writeback before update |
| `0012` | [a0c022c1da5b](https://github.com/torvalds/linux/commit/a0c022c1da5b) | ntfs: NULL vol->vol_ino in the load_system_files() error |
| `0013` | [338abaf0dc92](https://github.com/torvalds/linux/commit/338abaf0dc92) | ntfs: use fatal_signal_pending() for fallocate interruption |
| `0014` | [fca746064d56](https://github.com/torvalds/linux/commit/fca746064d56) | ntfs: avoid truncate and writeback deadlock |
| `0015` | [56a64ee0f99d](https://github.com/torvalds/linux/commit/56a64ee0f99d) | ntfs: fix volume flag update races |
| `0016` | [55af94ca0ee3](https://github.com/torvalds/linux/commit/55af94ca0ee3) | ntfs: set the volume dirty bit unconditionally on metadata |
| `0017` | [521978c4f444](https://github.com/torvalds/linux/commit/521978c4f444) | ntfs: sync the volume dirty bit with the recorded error state |
| `0018` | [5d0e57ea8e37](https://github.com/torvalds/linux/commit/5d0e57ea8e37) | ntfs: persist the dirty state after the final put_super() |
| `0019` | [4a1bb54f571c](https://github.com/torvalds/linux/commit/4a1bb54f571c) | ntfs: do not clear the volume dirty bit during sync |
| `0020` | [1a3883b3685c](https://github.com/torvalds/linux/commit/1a3883b3685c) | ntfs: check the dirty-state commit on remount and unmount |
| `0021` | [17a1edda75fd](https://github.com/torvalds/linux/commit/17a1edda75fd) | ntfs: fail remount on sync errors and keep the dirty bit on |
| `0022` | [fa5489ebc8bc](https://github.com/torvalds/linux/commit/fa5489ebc8bc) | ntfs: include the final partial cluster in sync writes |
| `0023` | [749357bd48c1](https://github.com/torvalds/linux/commit/749357bd48c1) | ntfs: mount hibernated volumes read-only regardless of |
| `0024` | [ca4366067205](https://github.com/torvalds/linux/commit/ca4366067205) | ntfs: validate attribute-list sizes before allocation |
| `0025` | [2b451a65658f](https://github.com/torvalds/linux/commit/2b451a65658f) | ntfs: do not map an unmappable runlist fragment as a hole |
| `0026` | [26e51efbcb60](https://github.com/torvalds/linux/commit/26e51efbcb60) | ntfs: do not turn an unmappable runlist fragment into |
| `0027` | [5562eaecdaf9](https://github.com/torvalds/linux/commit/5562eaecdaf9) | ntfs: fail the mount when $MFT needs its own extent records |
| `0028` | [e727ea7fc4e3](https://github.com/torvalds/linux/commit/e727ea7fc4e3) | ntfs: do not map a vcn as a hole when its runlist lookup |
| `0029` | [82a5e003ef09](https://github.com/torvalds/linux/commit/82a5e003ef09) | ntfs: fail the mount when $MFT's data size exceeds its |
| `0030` | [768c6f5fab58](https://github.com/torvalds/linux/commit/768c6f5fab58) | ntfs: hold the runlist lock while expanding a non-resident |
| `0031` | [258239e79b84](https://github.com/torvalds/linux/commit/258239e79b84) | ntfs: do not use a stale runlist pointer when undoing $MFT |
| `0032` | [c6ee0986b807](https://github.com/torvalds/linux/commit/c6ee0986b807) | ntfs: add a runlist merge that leaves the source runlist to |
| `0033` | [69ba74e8a5df](https://github.com/torvalds/linux/commit/69ba74e8a5df) | ntfs: balance the $MFT runlist lock in data extension error |
| `0034` | [16fcb1c446f1](https://github.com/torvalds/linux/commit/16fcb1c446f1) | ntfs: fix kunmap_local() of advanced pointers in |
| `0035` | [a5ec71084996](https://github.com/torvalds/linux/commit/a5ec71084996) | ntfs: fix kmap_local leak in ntfs_check_logfile() |
| `0036` | [9b32a74f4ef5](https://github.com/torvalds/linux/commit/9b32a74f4ef5) | ntfs: report block device flush failures from fsync |
| `0037` | [569f514f0ec7](https://github.com/torvalds/linux/commit/569f514f0ec7) | ntfs: flush the block device when syncing a directory |
| `0038` | [89467388e8af](https://github.com/torvalds/linux/commit/89467388e8af) | ntfs: roll back the ACL xattr commit when the WSL mode update |
| `0039` | 本地补丁，上游未修（namjaejeon/linux-ntfs#98） | ntfs: don't remount read-only when a read is interrupted |
| `0040` | 本地补丁，上游未修（ntfs-next 2b4bb6d6d 仍是可打断读取） | ntfs: don't let a fatal signal interrupt metadata updates |
