# Armbian 构建适配( RK3588 笔记本)

用于把 **Skysi X5**(及同模具的幽兰/开鸿、haitu、evb)接进 Armbian 构建。复制到 Armbian 构建树的对应位置使用。

## 目录

```
config/boards/            # 板级定义
  skysi-x5.conf           # 主板: 元数据 + 启动场景 + 音频用户态 hook
  evb-rk3588s.conf        # 参考板 (RK3588S evb1)
  haitu-rk3588.conf       # haitu 板
  leez-p710.conf          # leez p710
userpatches/
  config-*.conf           # 各板的 quick-build 配置(BOARD/BRANCH/RELEASE/DESKTOP)
  linux-rockchip64-edge.config   # 内核 config 覆盖
  kernel/archive/rockchip64-7.2/
    0001-add-rk3588-laptop-skysi-x5-and-haitu-board.patch
                            # 内核补丁: 新增 skysi-x5/haitu dts,并含
                            #   panel-edp、gsl3673 触控、cw2017 电池、
                            #   es7243e/es8326 codec 等驱动改动
  u-boot/legacy/u-boot-radxa-rk35xx/
    0001-add-skysi-x5-laptop-haitu-and-evb1-rk3588s.patch
                            # u-boot 补丁: 新增板级 dts + defconfig
```

## 板级要点(`config/boards/skysi-x5.conf`)

- `BOOTCONFIG=skysi-x5_defconfig`;`BOOT_SCENARIO=spl-blobs` + `BOOT_SPI_RKSPI_LOADER=yes`: 用厂商 u-boot 从 eMMC 引导(不覆盖 8MB NOR)。
- `BOOT_LOGO="desktop"`(桌面/Plymouth 启动图)。
- `post_family_tweaks__skysix5_naming_audios()`: 构建时写入镜像 —
  - `etc/wireplumber/wireplumber.conf.d/51-skysi-names.conf`(卡片/输出/输入英文命名);
  - `.../52-skysi-default.conf`(analog 输出优先级 1200,设默认);
  - `/usr/local/bin/skysi-audio-default.sh` + `systemd/user/skysi-audio-default.service`(登录激活 Speaker/Headphone 组合剖面 + L/R 均衡)。

> 音频修复的完整说明见 [`../audio/README.md`](../audio/README.md)。

## 构建

```bash
cd /home/user/armbian-build
./compile.sh x5
```

## 注意

- `kernel/userpatches` 放入 `archive/` 只在该补丁被 Armbian 的 patch 流程选中时生效;新版本内核目录若变化需同步路径。
- 内核代码改动本身在内核仓库(见 [`../dts_for_mainline`](../dts_for_mainline) 与内核 patch)。
