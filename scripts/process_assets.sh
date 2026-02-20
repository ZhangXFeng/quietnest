#!/bin/bash
# QuietNest 素材处理脚本
# 将下载的原始录音转换为引擎需要的格式：48kHz 16bit mono CAF
#
# 依赖：ffmpeg (brew install ffmpeg)
#
# 用法：
#   1. 将下载的原始文件放入 scripts/raw/ 目录
#   2. 运行 ./scripts/process_assets.sh
#   3. 处理后的文件输出到 QuietNest/Resources/Assets/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RAW_DIR="$SCRIPT_DIR/raw"
OUTPUT_DIR="$PROJECT_DIR/QuietNest/Resources/Assets"

# 检查依赖
if ! command -v ffmpeg &>/dev/null; then
    echo "❌ 需要安装 ffmpeg: brew install ffmpeg"
    exit 1
fi

# 创建目录
mkdir -p "$OUTPUT_DIR"
mkdir -p "$RAW_DIR"

if [ -z "$(ls -A "$RAW_DIR" 2>/dev/null)" ]; then
    echo "⚠️  请将原始音频文件放入 $RAW_DIR 目录"
    echo "   支持格式：wav, mp3, flac, ogg, aiff"
    echo ""
    echo "   文件命名规则（去掉后缀即为 soundId）："
    echo "   rain.wav -> soundId: rain"
    echo "   fireplace.mp3 -> soundId: fireplace"
    exit 0
fi

echo "🎵 开始处理素材..."
echo "   输入目录: $RAW_DIR"
echo "   输出目录: $OUTPUT_DIR"
echo ""

count=0
for f in "$RAW_DIR"/*; do
    [ -f "$f" ] || continue

    filename=$(basename "$f")
    name="${filename%.*}"
    output="$OUTPUT_DIR/${name}.caf"

    echo "  处理: $filename"

    # 步骤 1：转换为 48kHz mono
    # 步骤 2：截取前 60 秒（如果超过）
    # 步骤 3：电平归一化到 -6 LUFS
    # 步骤 4：淡入淡出（首尾各 0.5 秒）防止循环时的 click
    # 步骤 5：输出为 16bit PCM CAF
    ffmpeg -y -i "$f" \
        -ac 1 \
        -ar 48000 \
        -t 60 \
        -af "loudnorm=I=-6:TP=-1:LRA=7,afade=t=in:st=0:d=0.5,afade=t=out:st=59:d=1" \
        -c:a pcm_s16le \
        -f caf \
        "$output" \
        -loglevel warning

    # 显示信息
    duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$output" 2>/dev/null | cut -d. -f1)
    size=$(du -h "$output" | cut -f1)
    echo "    ✅ -> ${name}.caf (${duration}s, ${size})"

    count=$((count + 1))
done

echo ""
echo "✅ 处理完成！共 $count 个素材"
echo "   输出目录: $OUTPUT_DIR"

# 统计总大小
total_size=$(du -sh "$OUTPUT_DIR" | cut -f1)
echo "   总大小: $total_size"
