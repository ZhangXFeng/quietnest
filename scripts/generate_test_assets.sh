#!/bin/bash
# QuietNest 合成测试素材生成脚本
# 用 ffmpeg 合成近似声音，用于在获取真实录音前验证粒子合成管道
#
# 依赖：ffmpeg (brew install ffmpeg)
# 用法：./scripts/generate_test_assets.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/QuietNest/Resources/Assets"

if ! command -v ffmpeg &>/dev/null; then
    echo "❌ 需要安装 ffmpeg: brew install ffmpeg"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# 公共参数：48kHz mono 16bit CAF，60s
COMMON="-ac 1 -ar 48000 -t 60 -c:a pcm_s16le -f caf"

make_asset() {
    local name="$1"
    local filter="$2"
    local output="$OUTPUT_DIR/${name}.caf"
    echo "  生成: ${name}.caf"
    ffmpeg -y -f lavfi -i "$filter" \
        $COMMON \
        -af "afade=t=in:st=0:d=1,afade=t=out:st=59:d=1" \
        "$output" -loglevel error
}

echo "🎵 生成合成测试素材..."
echo "   输出目录: $OUTPUT_DIR"
echo ""

# 自然类（用带通滤波噪声近似质感）
make_asset "rain"        "anoisesrc=color=pink:amplitude=0.4[n];[n]lowpass=f=2000,highpass=f=200"
make_asset "ocean"       "anoisesrc=color=brown:amplitude=0.6[n];[n]lowpass=f=800,volume=2"
make_asset "stream"      "anoisesrc=color=white:amplitude=0.3[n];[n]bandpass=f=1200:width_type=o:w=3"
make_asset "wind"        "anoisesrc=color=pink:amplitude=0.25[n];[n]lowpass=f=600"
make_asset "thunder"     "anoisesrc=color=brown:amplitude=0.8[n];[n]lowpass=f=300,volume=3"
make_asset "birds"       "anoisesrc=color=white:amplitude=0.15[n];[n]bandpass=f=3000:width_type=o:w=2"
make_asset "frogs"       "anoisesrc=color=pink:amplitude=0.2[n];[n]bandpass=f=800:width_type=o:w=2"
make_asset "crickets"    "anoisesrc=color=white:amplitude=0.2[n];[n]bandpass=f=4000:width_type=o:w=1"
make_asset "campfire"    "anoisesrc=color=brown:amplitude=0.5[n];[n]lowpass=f=1000,highpass=f=80"
make_asset "leaves"      "anoisesrc=color=white:amplitude=0.18[n];[n]bandpass=f=2500:width_type=o:w=3"
make_asset "forest_wind" "anoisesrc=color=pink:amplitude=0.3[n];[n]lowpass=f=500"
make_asset "waterfall"   "anoisesrc=color=white:amplitude=0.5[n];[n]lowpass=f=3000,highpass=f=100"

# 城市类
make_asset "cafe"        "anoisesrc=color=pink:amplitude=0.3[n];[n]bandpass=f=1000:width_type=o:w=4"
make_asset "library"     "anoisesrc=color=brown:amplitude=0.1[n];[n]lowpass=f=400"
make_asset "clock"       "anoisesrc=color=white:amplitude=0.1[n];[n]bandpass=f=500:width_type=o:w=1"
make_asset "aircon"      "anoisesrc=color=pink:amplitude=0.2[n];[n]lowpass=f=300"
make_asset "fan"         "anoisesrc=color=pink:amplitude=0.25[n];[n]bandpass=f=200:width_type=o:w=3"
make_asset "train"       "anoisesrc=color=brown:amplitude=0.6[n];[n]lowpass=f=500,highpass=f=50"
make_asset "airplane"    "anoisesrc=color=pink:amplitude=0.5[n];[n]lowpass=f=400,highpass=f=80"
make_asset "driving"     "anoisesrc=color=brown:amplitude=0.4[n];[n]lowpass=f=600"
make_asset "night_street" "anoisesrc=color=pink:amplitude=0.2[n];[n]lowpass=f=1500"
make_asset "rain_window" "anoisesrc=color=white:amplitude=0.35[n];[n]lowpass=f=2500,highpass=f=150"

# 预设中用到的额外声音
make_asset "seagull"     "anoisesrc=color=white:amplitude=0.15[n];[n]bandpass=f=2000:width_type=o:w=2"
make_asset "jazz"        "anoisesrc=color=pink:amplitude=0.2[n];[n]bandpass=f=1500:width_type=o:w=4"
make_asset "cat"         "anoisesrc=color=pink:amplitude=0.1[n];[n]bandpass=f=600:width_type=o:w=2"
make_asset "blizzard"    "anoisesrc=color=white:amplitude=0.35[n];[n]lowpass=f=700"

echo ""
count=$(ls "$OUTPUT_DIR"/*.caf 2>/dev/null | wc -l | tr -d ' ')
total_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
echo "✅ 生成完成！共 $count 个素材，总大小 $total_size"
echo ""
echo "⚠️  这些是合成测试素材，用于验证粒子合成管道。"
echo "   正式版请替换为真实录音（放入 scripts/raw/ 后运行 process_assets.sh）。"
