#!/bin/bash
# Skysi X5: 每次登录后激活 "Speaker / Headphone"(组合剖面、设默认),并应用 L/R 平衡。
# 右声道(硬件)偏小 → 用 codec HPR 音量补偿;name 形式 cset,避免依赖 numid。
set -u
CARD=alsa_card.platform-analog-sound
SINK=alsa_output.platform-analog-sound.stereo-fallback

# 等待声卡出现(最长 ~10s)
for i in $(seq 1 40); do
	if pactl list cards short 2>/dev/null | grep -q "$CARD"; then
		break
	fi
	sleep 0.25
done

# 激活 输出+输入 组合剖面(扬声器/耳机 + 麦克风)
pactl set-card-profile "$CARD" output:stereo-fallback+input:stereo-fallback 2>/dev/null
sleep 0.5
# 设为默认
pactl set-default-sink "$SINK" 2>/dev/null

# L/R 均衡:右喇叭偏小,用 codec HPL/HPR 音量补偿
amixer -c 1 cset 'HPL Playback Volume' 152 2>/dev/null
amixer -c 1 cset 'HPR Playback Volume' 160 2>/dev/null

exit 0
