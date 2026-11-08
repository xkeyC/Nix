# PaperTracker：无线面捕/眼追（官方只有 Windows 版），用 Proton（经 umu）运行。
# 默认用 Steam 库里的 Proton Experimental：GE-Proton11-11 下，PaperTracker 建 SteamVR 叠加层时
# Proton 的 vrclient 桥断言失败（vroverlay_manual.c:505，前面是调用空函数指针），弹出模态的
# “Wine C++ Runtime Library”对话框把主线程卡死；同一时刻 vrclient 报取不到
# GetImageMemoryRequirements2KHR。PAPERTRACKER_PROTON=<Proton 目录> 可临时换别的版本。
# 菜单里的「PaperTracker」或命令 papertracker 启动；首次启动会自动装进 ~/.local/share/papertracker/pfx。
# 2026-10-26 在本机用 7.3.28 跑通过，SteamVR 叠加层也能用。下面每条修正都对应当时踩过的坑。
#
#   * 设备每秒收到客户端的局域网广播后，把握手和图像流用 UDP 发到 45454 端口，防火墙要放行，
#     否则表现为“设备找不到 PC”。OSC（9000/9001）只走回环，不用放行。
#   * Proton 自带 vrclient 桥，Windows 版 openvr_api 经它连到 Linux 的 SteamVR（叠加层、校准都靠它）。
#     PaperTracker 用 Windows 进程表找 vrserver.exe 判断 SteamVR 是否运行，Linux 的 vrserver 不在其中，
#     所以用 vrwatch.exe 在 wine 里维护同名占位进程，并在 SteamVR 后启动时重做 vrclient 的注册表初始化，
#     见 packages/papertracker/vrwatch.c。
#   * 不让它碰 OpenXR：wineopenxr 建测试实例时会把 SteamVR 拉起来，没连头显时 vrserver 立刻退出，
#     Steam 却一直显示“SteamVR 运行中”。OpenXR 运行时指向不存在的文件即可；不能用 wineopenxr=d
#     禁用 DLL，那样 vkd3d-proton 建 DirectML 设备会卡死。
#   * 中文乱码：系统里的 Noto CJK 是 CFF2 可变字体，wine 渲染不了，前缀里放静态字体并设字体替换。
#   * KDE 两块屏都是 200% 缩放，wine 默认 96 DPI，窗口会缩成一小块，这里设成 192。
#
# Steam 用「Steam（UU 加速）」启动时，SteamVR 和 VRChat 在网络命名空间 uu 里，启动器经 steamvr-netns
# 跟进去（要在 Steam 之后启动）。这时设备的 UDP 45454 由 uu 空间的防火墙放行，见 uuplugin.nix。
{ pkgs, steamvrNetns, ... }:

let
  installer = pkgs.fetchurl {
    url = "https://oss2.papertracker.top/client/full/PaperTracker_7.4.0.exe";
    hash = "sha256-02bHxRr0NNZZTMIDkFNzwvfrcyEdgT4/tBojU5ijsd0=";
  };

  # Steam 装在第二个库里的 Proton Experimental（Steam 自己更新它）。
  protonExperimental = "/mnt/application/SteamLibrary/steamapps/common/Proton - Experimental";

  vrwatch = pkgs.runCommand "papertracker-vrwatch" { nativeBuildInputs = [ pkgs.zig ]; } ''
    export XDG_CACHE_HOME=$TMPDIR
    mkdir -p $out
    zig cc -target x86_64-windows-gnu -municode -Wl,--subsystem,windows -O2 -o $out/vrwatch.exe ${./packages/papertracker/vrwatch.c}
  '';

  fonts = [
    "${pkgs.noto-fonts-cjk-sans-static}/share/fonts/opentype/noto-cjk/NotoSansCJK-Regular.ttc"
    "${pkgs.noto-fonts-cjk-sans-static}/share/fonts/opentype/noto-cjk/NotoSansCJK-Bold.ttc"
    "${pkgs.wqy_microhei}/share/fonts/truetype/wqy-microhei.ttc"
  ];

  # 字体替换、GDI 字体链接（西文 UI 字体缺字时回退到中文字体）、抗锯齿和 DPI。
  # Version 5.00 格式的 .reg 必须是 UTF-16LE：写成 UTF-8 时 wine 的 regedit 会丢掉中文键名，
  # 还会把 hex(7) 的 UTF-16 字节当单字节字符再转一遍，字体链接就成了 "N\0o\0t\0o…"。
  prefixReg = pkgs.runCommand "papertracker-prefix.reg" { nativeBuildInputs = [ pkgs.glibc.bin ]; } ''
    { printf '\xff\xfe'; iconv -f UTF-8 -t UTF-16LE ${prefixRegText}; } > $out
  '';
  prefixRegText = pkgs.writeText "papertracker-prefix-utf8.reg" (
    let
      replaced = [ "Microsoft YaHei" "Microsoft YaHei UI" "微软雅黑" "SimSun" "NSimSun" "宋体" "新宋体"
                   "SimHei" "黑体" "DengXian" "等线" "PMingLiU" "MingLiU" "Microsoft JhengHei" "MS UI Gothic" ];
      linked = [ "Tahoma" "Segoe UI" "Microsoft Sans Serif" "MS Shell Dlg" "MS Shell Dlg 2" "Arial" "Lucida Sans Unicode" ];
      # REG_MULTI_SZ：NotoSansCJK-Regular.ttc,Noto Sans CJK SC \0 wqy-microhei.ttc,WenQuanYi Micro Hei \0\0
      link = "hex(7):4e,00,6f,00,74,00,6f,00,53,00,61,00,6e,00,73,00,43,00,4a,00,4b,00,2d,00,52,00,65,00,67,00,75,00,6c,00,61,00,72,00,2e,00,74,00,74,00,63,00,2c,00,4e,00,6f,00,74,00,6f,00,20,00,53,00,61,00,6e,00,73,00,20,00,43,00,4a,00,4b,00,20,00,53,00,43,00,00,00,77,00,71,00,79,00,2d,00,6d,00,69,00,63,00,72,00,6f,00,68,00,65,00,69,00,2e,00,74,00,74,00,63,00,2c,00,57,00,65,00,6e,00,51,00,75,00,61,00,6e,00,59,00,69,00,20,00,4d,00,69,00,63,00,72,00,6f,00,20,00,48,00,65,00,69,00,00,00,00,00";
      line = s: s + "\r\n";
    in
    pkgs.lib.concatMapStrings line (
      [ "Windows Registry Editor Version 5.00" "" "[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]" ]
      ++ map (f: ''"${f}"="Noto Sans CJK SC"'') replaced
      ++ [ "" "[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink]" ]
      ++ map (f: ''"${f}"=${link}'') linked
      ++ [
        ""
        "[HKEY_CURRENT_USER\\Control Panel\\Desktop]"
        ''"FontSmoothing"="2"''
        ''"FontSmoothingType"=dword:00000002''
        ''"FontSmoothingGamma"=dword:00000578''
        ''"FontSmoothingOrientation"=dword:00000001''
        ''"LogPixels"=dword:000000c0''
        ""
        "[HKEY_CURRENT_USER\\Software\\Wine\\Fonts]"
        ''"LogPixels"=dword:000000c0''
        ""
      ]
    )
  );

  papertracker = pkgs.writeShellApplication {
    name = "papertracker";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.umu-launcher ];
    text = ''
      data="''${XDG_DATA_HOME:-$HOME/.local/share}/papertracker"
      export WINEPREFIX="$data/pfx"
      export GAMEID=umu-papertracker STORE=none
      proton="''${PAPERTRACKER_PROTON:-${protonExperimental}}"
      if [ ! -x "$proton/proton" ]; then
        echo "papertracker: 找不到 $proton，改用 GE-Proton" >&2
        proton=${pkgs.proton-ge-bin.steamcompattool}
      fi
      export PROTONPATH="$proton"

      # 每次启动的日志单独放一个目录（logs/latest 指向最新一次），保留最近 10 次。
      # vrwatch 启动时会覆盖前缀里的 vrwatch.log，所以先把上一次的挪进上一次的目录。
      logs="$data/logs"
      shim="$WINEPREFIX/drive_c/papertracker-shim"
      run="$logs/$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$run"
      if [ -f "$shim/vrwatch.log" ] && [ -d "$logs/latest" ]; then
        mv "$shim/vrwatch.log" "$logs/latest/"
      fi
      ln -sfn "$run" "$logs/latest"
      find "$logs" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | head -n -10 | xargs -r rm -rf
      echo "papertracker: Proton $(cat "$proton/version" 2>/dev/null || echo "$proton")，日志在 $run" >&2
      export PROTON_LOG="''${PROTON_LOG:-1}" PROTON_LOG_DIR="$run"
      export XR_RUNTIME_JSON="$data/no-openxr-runtime.json"
      # Proton 的手柄无障碍助手启动时也会碰 DXVK/OpenXR，这里用不上。
      export PROTON_USE_XALIA=0
      mkdir -p "$logs"

      appdir="$WINEPREFIX/drive_c/users/steamuser/AppData/Local/Programs/Paper_Tracker"
      if [ ! -f "$appdir/PaperTracker.exe" ]; then
        echo "papertracker: 首次运行，正在安装到 $WINEPREFIX"
        # umu/Proton 跑在容器里，看不到宿主的 /tmp，安装包和注册表文件都放进前缀。
        mkdir -p "$WINEPREFIX/drive_c"
        cp ${installer} "$WINEPREFIX/drive_c/PaperTracker_Setup.exe"
        umu-run 'C:\PaperTracker_Setup.exe' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- \
          > "$data/logs/install.log" 2>&1 || true
        rm -f "$WINEPREFIX/drive_c/PaperTracker_Setup.exe"
        [ -f "$appdir/PaperTracker.exe" ] || { echo "papertracker: 安装失败，见 $data/logs/install.log" >&2; exit 1; }

        install -Dm644 -t "$WINEPREFIX/drive_c/windows/Fonts" ${pkgs.lib.escapeShellArgs fonts}
        cp ${prefixReg} "$WINEPREFIX/drive_c/papertracker-prefix.reg"
        umu-run regedit /S 'C:\papertracker-prefix.reg' > "$data/logs/regedit.log" 2>&1 || true
        rm -f "$WINEPREFIX/drive_c/papertracker-prefix.reg"
      fi

      # VRChat 的输出日志在它自己的 Proton 前缀里，PaperTracker 靠它跟踪换模；容器默认看不到 /mnt。
      vrchat_locallow=/mnt/data/SteamLibrary/steamapps/compatdata/438100/pfx/drive_c/users/steamuser/AppData/LocalLow/VRChat
      if [ -d "$vrchat_locallow" ]; then
        export PRESSURE_VESSEL_FILESYSTEMS_RW="$vrchat_locallow''${PRESSURE_VESSEL_FILESYSTEMS_RW:+:$PRESSURE_VESSEL_FILESYSTEMS_RW}"
        link="$WINEPREFIX/drive_c/users/steamuser/AppData/LocalLow/VRChat"
        mkdir -p "$(dirname "$link")"
        [ -L "$link" ] || { rm -rf "$link"; ln -s "$vrchat_locallow" "$link"; }
      fi

      mkdir -p "$shim"
      install -m755 ${vrwatch}/vrwatch.exe "$shim/vrwatch.exe"
      cd "$appdir"
      # 和 SteamVR、VRChat 进同一个网络命名空间：vrclient 桥要连 vrserver，OSC 发往 VRChat 的 127.0.0.1。
      exec ${steamvrNetns}/bin/steamvr-netns umu-run 'C:\papertracker-shim\vrwatch.exe' \
        'C:\users\steamuser\AppData\Local\Programs\Paper_Tracker\PaperTracker.exe' "$@"
    '';
  };
in
{
  networking.firewall.allowedUDPPorts = [ 45454 ];

  environment.systemPackages = [
    papertracker
    (pkgs.makeDesktopItem {
      name = "papertracker";
      desktopName = "PaperTracker";
      comment = "VR 面捕/眼追（GE-Proton）";
      exec = "papertracker";
      icon = "applications-games";
      categories = [ "Game" ];
    })
  ];
}
