# Skysi X5 音频修复

> 设备: 深圳天思 Skysi X5 / 幽兰(YourLand)同模具, RK3588, Armbian `rockchip64` edge(主线 7.2.x)。
> 目标: 让板载 ES8326 codec 的**扬声器 / 耳机 / 内麦**在主线内核下正常出声、可切换、可均衡。
> 状态: 已完成并实机验证通过(默认 Speaker/Headphone, 插拔耳机即时静音/恢复扬声器, L/R 均衡)。

---

## 一、音频拓扑

| 器件 | 位置 | 作用 |
|---|---|---|
| ES8326 | i2c3 @0x19 | 音频 codec(驱动喇叭 + 耳机 + 内麦) |
| ES7243E | i2c3 @0x10 | 麦克风阵列 ADC(dmic) |
| speaker 功放 | GPIO2 PB7 | 扬声器使能(高=开) |
| headphone 检测 | GPIO1 PD0 | 插拔耳机中断 |
| I2S0_8CH | — | 与 codec 的 PCM 总线 |
| MCLK to-IO | GRF `I2S0_8CH_MCLKOUT_TO_IO` | 给 codec 的时钟门(主线接管) |

---

## 二、根因与修复(核心)

### 1. MCLK 引脚门被主线内核关闭 —— 完全无声
主线 `clk: rockchip: rk3588: add GATE_GRF clocks for I2S MCLK output to IO` 把 MCLK to-IO 交给内核管理。旧 dtb 只引用了内部 mux `I2S0_8CH_MCLKOUT`,没引用 to-pin 门 → codec 拿不到 MCLK → 无声。
**修复**(`rk3588-skysi-x5.dts` es8326 节点):
```dts
clocks = <&cru I2S0_8CH_MCLKOUT_TO_IO>;
clock-names = "mclk";
assigned-clocks = <&cru I2S0_8CH_MCLKOUT>;
assigned-clock-rates = <12288000>;
```

### 2. I2S 主从方向错误 —— 无输出 sink / 不出时钟
`rockchip_i2s_tdm_set_fmt()` 只接受 `CBP_CFP`(CPU 主)或 `BC_FC`(CPU 从)。若 simple-card 未声明 master,会回退成 `CBC_CFC`,CPU 被设为从机,codec 也是从机 → 谁都不出 BCLK/LRCK。
**修复**(`rk3588-skysi-x5.dts` analog-sound 节点):
```dts
simple-audio-card,bitclock-master = <&es8326>;
simple-audio-card,frame-master   = <&es8326>;
```

### 3. 耳机检测不运行 + 扬声器功放无法切换
simple-audio-card 不调用 `snd_soc_component_set_jack`,→ `es8326->jack` 恒为 NULL → 检测逻辑从不执行,功放只能常开。
**修复**(`sound/soc/codecs/es8326.c`):
- `es8326_set_dai_fmt()` 接受 `SND_SOC_DAIFMT_CBP_CFP`(CPU 主时 codec 保持从机)。
- jack 相关路径全部**空指针保护**(`if (es8326->jack && …)`),绝不因 jack 为 NULL 而中断检测。
- `es8326_irq` 始终调度 `jack_detect_work`(插拔耳机即时响应)。
- probe 默认 `spk_con` 高(扬声器开);检测到耳机 → `gpiod_set_value_cansleep(spk_con, 0)` 关功放,拔出 → 拉高。
- dtb 增加 `spk-con-gpio = <&gpio2 RK_PB7 GPIO_ACTIVE_HIGH>` 与 `hp_detect` 引脚。

### 4. 用户态: 命名 / 默认输出 / L/R 均衡
桌面端用 WirePlumber + 登录自启脚本实现:
- `wireplumber/51-skysi-names.conf`: 把 analog 卡/输出命名为 **Speaker / Headphone**、HDMI 命名为 **HDMI**、内麦 **Internal Microphone**(英文,便于区分)。
- `wireplumber/52-skysi-default.conf`: 给 analog 输出设 `priority.session/driver = 1200`,使其成为默认。
- `skysi-audio-default.sh` + `.service`: 登录后激活 `output:stereo-fallback+input:stereo-fallback` 组合剖面、设为默认 sink,并应用 **L/R 平衡**(右声道硬件偏小,HPL=152 / HPR=160,`name` 形式 cset)。

---

## 三、持久化在哪(重要)

| 改动 | 落点 |
|---|---|
| 内核 dts + es8326.c(上面第 1~3 点) | 内核仓库,已提交,内核 HEAD `7a6f6a223005`(dts + codec 合并在一枚提交)。 |
| WirePlumber 规则 + 登录默认/均衡脚本(第 4 点) | **`armbian-build/config/boards/skysi-x5.conf`** 的 `post_family_tweaks__skysix5_naming_audios()`,构建时写入镜像。 |
| 本目录下的 4 个源文件 | `51/52` conf、`default.sh`、`.service` —— 与 board conf 内嵌内容一致,作为**可读的权威副本**。 |

> 即: 用户态修复已由构建固化,无需在已装系统的 `/etc` 里再手工改。

---

## 四、文件说明

- `wireplumber-51-skysi-names.conf` / `wireplumber-52-skysi-default.conf` / `skysi-audio-default.sh` / `skysi-audio-default.service`: 上面第 4 点的源文件。
- `skysi-audio-diag.sh`: 只读诊断脚本(root),重启后自动抓声卡/剖面/MCLK/寄存器并播测试音,定位"有卡无声"。

---

## 五、验证

```bash
# 检查剖面可用性与默认
wpctl status | sed -n '/Sinks:/,/Sources:/p'
pactl list cards | grep -A30 'platform-analog-sound' | grep -iE 'Active Profile|available:'

# 出声测试(插/拔耳机应切换,开机即插耳机应静音扬声器)
speaker-test -c2 -t wav -l1
```

---

## 六、已知限制 / 后续

- **耳机图标仍显示为"扬声器"**: 纯视觉;音频行为已正确。要做成"耳机图标"需走机器驱动 `set_jack` 或解决 UCM 加载(独立课题)。
- **ES7243E(dmic)**: 已改 compatible 为 `ES7243E_MicArray_0` 并修正 pdm 引脚,但驱动/配置仍需确认。
- **RTL8852BS / AP6275S 蓝牙**: 独立于音频,需 `rtl_bt` 固件(见 `/lib/firmware/rtlbt/rtl8852bs_*`)。
- 上主线: 建议把 `CBP_CFP` 与 jack 空指针保护拆成独立小补丁再提交。
