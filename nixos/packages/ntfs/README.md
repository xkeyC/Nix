# ntfs 驱动补丁

内核 7.1 起自带的新 ntfs 驱动（Namjae Jeon）的补丁，由 `nixos/storage.nix` 按文件名顺序全部加到
`boot.kernelPatches`。基于 7.3.4，按顺序全部能用 `git apply` 干净打上（2026-11-11 验证）。

## 组成

- `0001`：上游 8deea344965f 移植到 7.3 的版本（7.3 的 inode.c 缺 `ntfs_non_resident_sizes_inconsistent()` 上下文）。
  7.3 把稀疏文件的后续段（扩展 MFT 记录里 lowest_vcn ≠ 0 的 $DATA）误判为损坏：只有第一段带
  compressed_size 字段，校验却要求每一段都有。Steam、网盘下载器在 Windows 下创建的都是稀疏文件，
  读碎片多的大文件时报 “Corrupt 0x80 attribute”，整块盘被重新挂载为只读。
- `0002`–`0038`（已删）：v7.3 → v7.4-rc1 之间所有带 `Cc: stable` 的 `fs/ntfs` 修复（37 个），7.3.4 已全部包含
  （按上游提交号逐个核对 ChangeLog-7.3.4），2026-11-11 升到 7.3.4 时删除。其中 `7823d72305f0`（trigger page_mkwrite
  for native 4Kn size extension）修了 ntfs_fallocate() 并发写入时丢数据（2026-11-04 qcow2 实测丢过），
  所以内核不要低于 7.3.4。
- `0039`：本地补丁。进程等待目录或 inode 读取时被杀（kill、Ctrl+C、程序退出），读取返回 -EINTR，驱动把它当
  卷错误（日志 “error code -4” 或 “Failed to read full index block”），整块盘变只读。
- `0040`：本地补丁。元数据读取被致命信号打断（返回 -EINTR）时，驱动报卷错误、整块盘变只读；如果读取发生在更新
  途中，更新还会停在一半：unlink() 释放簇和 MFT 记录、删除目录项时改目录索引、分配簇或 MFT 记录。日志
  “Failed to map first page (error -4)”、“Leaving inconsistent metadata”、“ntfs_index_remove(): Delete failed”、
  “ntfs_cluster_alloc(): ... (error -4)”、“Failed to map directory index page, error 4”。磁盘上会留下没释放的簇、
  没目录项的 MFT 记录或坏掉的目录索引。2026-11-07 关机时 QQ 删 SQLite -wal 就是这样。
  补丁在 aops.c 加 `ntfs_read_metadata_folio()`：读法和 read_mapping_folio() 一样，但不可打断地等读取完成、
  持页锁检查结果，不会返回 -EINTR。用于全部元数据读取（位图、MFT、$MFTMirr、属性读写即目录索引块、目录查找、
  ntfs_attr_set、清空 $LogFile 的块设备读改写）；挂载时的检查、压缩文件数据和命名流内容不变（7.3 没有命名流）。
  它也覆盖了 0039 处理的查找情况（namjaejeon/linux-ntfs#98）；0039 留着无害，上游合入 0040 后两个一起删。
  上游提交在 xkeyC/linux-ntfs 的 fix-eintr-metadata-update 分支（v3）。
  验证（QEMU，读取限速 40 IOPS，drop_caches 后中途 kill，每个场景 20 次）：删分散在不同 $Bitmap 页的小文件、删跨
  4 个 $Bitmap 页的大文件、在 4000 个长文件名的目录里删文件、ls -l 这个目录、fallocate、dd conv=fsync。不带 0040 时
  每个场景都会变只读，删文件的场景 ntfsck 报 $Bitmap、MFT 和索引损坏（7.3.1 + 0001–0039 删目录项第 2 次就坏了
  整个目录索引，ntfsck 报 4001 个错误）；带上后全部不变只读、ntfsck 干净。ntfs-next（KASAN + lockdep，SIGKILL 和
  SIGTERM）和 7.3.1（SIGKILL）都验证过；ntfs-next 上另外验证了读取被打断后又失败（dm-delay + fail_make_request）
  时返回 -EIO、进程正常退出。没能触发的：在大目录里建文件（kill 都落在之前的查找里）。
  代价：被杀的进程要等正在进行的那次元数据读取完成；设备一直不返回时（如 multipath queue_if_no_path）会停在 D 状态。

## 什么时候删

- 内核升级后先看哪些已经包含：从 GitHub（gregkh/linux，sparse clone `fs/ntfs`）取新内核源码，对每个补丁跑
  `git apply -R --check`，能反向打上的就是已包含，删掉；上游补丁也可以按提交号在 kernel.org 的 ChangeLog 里查。
  只删除代码的补丁反向测试可能误判，以源码为准。
- `0001` 不在 7.3.4 里；升到 7.4 后应已包含。`0039`、`0040` 要等上游修复。
- 剩下的补丁换到新内核上若有冲突，按上游提交重新移植，保持文件名顺序。

## 清单

| 序号 | 来源 | 标题 |
|---|---|---|
| `0001` | [8deea344965f](https://github.com/torvalds/linux/commit/8deea344965f)，移植到 7.3 | ntfs: only require compressed size on first extent |
| `0002`–`0038` | 已包含在 7.3.4，已删 | v7.3 → v7.4-rc1 的 `Cc: stable` 修复 |
| `0039` | 本地补丁，上游未修（namjaejeon/linux-ntfs#98） | ntfs: don't remount read-only when a read is interrupted |
| `0040` | 本地补丁，上游未修（ntfs-next 2b4bb6d6d 仍是可打断读取） | ntfs: don't let a fatal signal interrupt metadata reads |
