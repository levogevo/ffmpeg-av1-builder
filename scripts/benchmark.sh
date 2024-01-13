#!/bin/bash

BASE_DIR=$(pwd)
BENCHMARK_DIR="$BASE_DIR/benchmark"
INPUT_DIR="$BENCHMARK_DIR/input"
OUTPUT_DIR="$BENCHMARK_DIR/output"

mkdir -p "$INPUT_DIR"

# input names
INPUT=('waves_crashing.mp4' 'burning_wood.mp4' 'mountain_scenery.mp4')

# standard 4k 24fps stock video
test -f "$INPUT_DIR/${INPUT[0]}" || wget -O "$INPUT_DIR/${INPUT[0]}" 'https://www.pexels.com/download/video/1390942/?fps=23.98&h=2160&w=4096'
test -f "$INPUT_DIR/${INPUT[1]}" || wget -O "$INPUT_DIR/${INPUT[1]}" 'https://www.pexels.com/download/video/2908575/?fps=23.976&h=2160&w=4096'
test -f "$INPUT_DIR/${INPUT[2]}" || wget -O "$INPUT_DIR/${INPUT[2]}" 'https://www.pexels.com/download/video/5598970/?fps=23.976&h=2160&w=3840'

rm -rf "$OUTPUT_DIR" && mkdir -p "$OUTPUT_DIR"

# Different variables to test
CRF=(40)
ENCODER=('libsvtav1' 'librav1e' 'libaom-av1')
ENCODER=('libsvtav1')
PRESET=(13)

# Log for results
LOG="$OUTPUT_DIR/results.txt"

for input in "${INPUT[@]}"
do
    # echo "$input"
    for encoder in "${ENCODER[@]}"
    do
        for preset in "${PRESET[@]}"
        do
            for crf in "${CRF[@]}"
            do
                OUTPUT="$OUTPUT_DIR/${encoder}_preset${preset}_crf${crf}_$input"
                echo "output: $OUTPUT" >> "$LOG"
                TIME_BEFORE=$(date +%s)
                ffmpeg -i "$INPUT_DIR/$input" -c:a copy -c:v "$encoder" -preset "$preset" -crf "$crf" "$OUTPUT" 2> /dev/null || exit 1
                TIME_AFTER=$(date +%s)
                TIME_DIFF=$((TIME_AFTER - TIME_BEFORE))
                echo -e "\t time taken: $TIME_DIFF" >> "$LOG"
                ffmpeg -i "$OUTPUT" -i "$INPUT_DIR/$input" -lavfi libvmaf=n_threads="$(nproc)" -f 'null' - | grep "VMAF score:" >> "$LOG" || exit 1
            done
        done    
    done
done