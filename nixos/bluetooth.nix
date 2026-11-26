# 蓝牙：板载 MediaTek MT7922（和 Wi-Fi 同一张卡，PCI mt7921e / USB btusb+btmtk）。
# 内核驱动和固件（linux-firmware 的 mediatek/BT_RAM_CODE_MT7922_*）本来就有，
# 缺的是用户态的 BlueZ；开启后 Plasma 会自动带上 BlueDevil（托盘图标和系统设置里的蓝牙页面）。
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # Experimental：让 BlueZ 通过 D-Bus 报告耳机电量，Plasma 托盘里能看到。
    settings.General.Experimental = true;
  };

  # 音频编码：nixpkgs 的 PipeWire 已带 LDAC（ldacbt）、aptX / aptX HD、AAC、LC3 等编码插件，
  # 不用另装。耳机支持 LDAC 时 PipeWire 会优先选它；也可在 Plasma 音频设置里对蓝牙设备手动切换「配置」。
  # LDAC 码率保持默认的自适应（auto，信号差时在 990/660/330 kbps 之间降档），固定 990 kbps 容易断音。
  # SBC-XQ：只支持 SBC 的设备用更高码率的 SBC。
  services.pipewire.wireplumber.extraConfig."50-bluez"."monitor.bluez.properties" = {
    "bluez5.enable-sbc-xq" = true;
  };
}
