# 从 CachyOS 内核（CONFIG_CACHY）搬过来的调优。这些补丁只是改了内核参数的默认值，
# 用 sysctl / sysfs / 启动参数就能得到同样的效果，不用换内核，也不用加补丁。
# 来源：https://github.com/CachyOS/linux 的 7.3/cachy 分支，经 xddxdd/nix-cachyos-kernel 了解到。
#
# 没搬的：split lock 缓解（Zen4 没有 split_lock_detect，开关无效）、swappiness 100（没有 swap）、
# SCHED_NR_MIGRATE_BREAK 8（编译期常量，要改源码）。
{ ... }:

{
  # CachyOS 的默认抢占模式是 full；nixpkgs 内核带 PREEMPT_DYNAMIC，默认是 lazy。
  # THP 改为 always，和下面的 defer+madvise 配合：未 madvise 的进程分配失败时只在后台整理，不会卡住。
  boot.kernelParams = [ "preempt=full" "transparent_hugepage=always" ];

  boot.kernel.sysctl = {
    # 关闭主动内存整理：按需整理就够了，后台整理会无故占用 CPU。
    "vm.compaction_proactiveness" = 0;
    # 关闭水位提升：kswapd 会提前回收正在用的页，内存紧张时容易造成反复缺页、卡顿。
    "vm.watermark_boost_factor" = 0;
  };

  systemd.tmpfiles.rules = [
    # THP 缺页分配失败时，madvise 的进程照常同步整理，其他进程交给 kswapd/kcompactd 在后台整理。
    "w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise"
    # MGLRU 保护最近 100 ms 访问过的页（CachyOS 设为 100 jiffies，HZ=1000），内存不足时先触发 OOM 而不是卡死。
    "w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 100"
  ];

  # EEVDF 调优只能通过 debugfs 设置，要等 debugfs 挂载后再写。
  # CachyOS 把归一化 base slice 从 0.7 ms 降到 0.4 ms；16 线程下内核按 1+log2(8)=4 倍放大，
  # 实际值从 2.8 ms 变为 1.6 ms。migration_cost 从 0.5 ms 降到 0.4 ms（不放大）。
  # 当前值：sudo cat /sys/kernel/debug/sched/{base_slice_ns,migration_cost_ns}
  systemd.services.cachy-sched-tuning = {
    description = "Apply CachyOS EEVDF scheduler tuning";
    wantedBy = [ "sysinit.target" ];
    after = [ "sys-kernel-debug.mount" ];
    unitConfig = {
      DefaultDependencies = false;
      RequiresMountsFor = "/sys/kernel/debug";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo 1600000 > /sys/kernel/debug/sched/base_slice_ns
      echo 400000 > /sys/kernel/debug/sched/migration_cost_ns
    '';
  };
}
