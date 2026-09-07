#!/bin/bash
# ============================================================================
# Skysi X5 音频诊断脚本(root 运行)
#   用途:重启后排查 es8326 声卡"注册了但没声音/无输出 sink"问题。
#   运行:  sudo bash /home/user/linux/skysi-audio-diag.sh
#   说明: 只读取状态 + 播放一次测试音,不修改任何配置。
# ============================================================================

echo "==================== 一、基本声卡信息 ===================="
cat /proc/asound/cards
echo
echo "--- 设备树 master 属性是否已加载(应为 2,代表已生效) ---"
echo "bitclock/frame-master 计数: $(ls /proc/device-tree/analog-sound/ 2>/dev/null | grep -c master)"
echo "es8326 mclk clock id(应为 0x2d2 = 722): "
cat /proc/device-tree/i2c@feab0000/audio-codec@19/clocks 2>/dev/null | od -An -tx4

echo
echo "==================== 二、PipeWire 设备/剖面 ===================="
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
wpctl status 2>/dev/null | sed -n '/Audio/,/Streams/p'
echo "--- analog 卡 active profile(应含 output:stereo-fallback) ---"
pactl list cards 2>/dev/null | grep -A20 'platform-analog-sound' | grep -iE 'Name:|Active Profile|device.profile.name' | head -12

echo
echo "==================== 三、I2S MCLK 时钟状态 ===================="
for c in i2s0_8ch_mclkout_to_io i2s0_8ch_mclkout mclk_i2s0_8ch_tx; do
  p="/sys/kernel/debug/clk/$c"
  printf '%-28s rate=%s enable=%s\n' "$c" "$(cat $p/clk_rate 2>/dev/null)" "$(cat $p/clk_enable_count 2>/dev/null)"
done

echo
echo "==================== 四、I2C 总线 3 上的设备 ===================="
which i2cdetect >/dev/null 2>&1 && i2cdetect -y -r 3 2>/dev/null || echo "缺少 i2c-tools(i2cdetect),请 apt install i2c-tools"

echo
echo "==================== 五、ES8326 关键寄存器(应有响应) ===================="
# 地址 0x19 在 i2c-3; i2ctransfer 做普通 I2C 读
reg_read() { i2ctransfer -y 3 w1@0x19 $1 r1 2>/dev/null; }
printf '%-18s %-10s %s\n' "REG" "VAL" "含义"
for r in 0x00 0x14 0x16 0x24 0x25 0x26 0x27 0x28 0x4f 0x57 0x58 0xf5 0xf6 0xf7 0xfd 0xfe 0xff; do
  v=$(reg_read "$r")
  printf '%-18s %-10s\n' "$r" "${v:-<no-response!>}"
done
echo "  参考: 0xfd/0xfe/0xff=CHIP_ID/VERSION(有值=芯片在响应); 0x16 ANA_PDN(0=功放供电开); 0x14 DAC_MUTE(3=静音); 0x25 DAC2HPMIX(0x88~0xa8=两路 HP 混音开); 0xf7 HP_MISC(0xfd=立体声配置,高位0xC0)"

echo
echo "==================== 六、扬声器功放 GPIO(gpio2 PB7) ===================="
# 需要 debugfs;普通用户无权限时 root 可读
grep -E 'gpio-1[45][0-9]|speaker|PB7' /sys/kernel/debug/gpio 2>/dev/null | grep -iE 'pb7|15[0-9]' | head || echo "(可忽略,读到更好)"

echo
echo "==================== 七、播放测试音并观察状态 ===================="
echo "--- 播放前流状态 ---"
cat /proc/asound/card1/pcm0p/sub0/status 2>/dev/null | head -4
echo "--- 播放 1 秒 440Hz(请确认能否听到) ---"
timeout 8 speaker-test -c2 -t sine -f 440 -l1 2>&1 | tail -5 || echo "speaker-test 失败或超时(若无输出 sink 属正常)"
echo "--- 播放后流状态(触发后应 RUNNING) ---"
cat /proc/asound/card1/pcm0p/sub0/status 2>/dev/null | head -4
echo "--- 触发时 hw 参数(采样率/位数) ---"
cat /proc/asound/card1/pcm0p/sub0/hw_params 2>/dev/null | grep -E 'format|rate|channels' | head

echo
echo "==================== 八、内核日志相关 ===================="
dmesg 2>/dev/null | grep -iE 'es8326|es7243|rockchip-i2s|i2s0_8ch|mclk|pdm1' | tail -30
echo "--- (es8326 若打印 set_fmt/参数错误会在这看到) ---"

echo
echo "==================== 完成 ===================="
echo "把以上输出贴回来即可;重点关注: 二是否出现 output:stereo-fallback、三的 enable/rate、五的 0xfd/0xff 是否有值、七是否 RUNNING。"
