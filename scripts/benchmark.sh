#!/bin/bash

BASE_DIR=$(pwd)
BENCHMARK_DIR="$BASE_DIR/benchmark"
DL_DIR="$BENCHMARK_DIR/downloads"
INPUT_DIR="$BENCHMARK_DIR/input"
OUTPUT_DIR="$BENCHMARK_DIR/output"

# input names and respective URLs
INPUT[0]='waves_crashing.mp4'
URL_DL[0]='https://www.pexels.com/download/video/1390942/?fps=23.98&h=2160&w=4096'
INPUT[1]='burning_wood.mp4'
URL_DL[1]='https://www.pexels.com/download/video/2908575/?fps=23.976&h=2160&w=4096'
INPUT[2]='gpac_chimera.mp4'
URL_DL[2]='http://download.opencontent.netflix.com.s3.amazonaws.com/gpac/GPAC_Chimera_AVCMain_AACLC_10s.mp4'
INPUT[3]='B_1.mp4'
URL_DL[3]='http://download.opencontent.netflix.com.s3.amazonaws.com/AV1/DVB-DASH/B_1.mp4'
INPUT[4]='D_2.mp4'
URL_DL[4]='http://download.opencontent.netflix.com.s3.amazonaws.com/AV1/DVB-DASH/D_2.mp4'

# download videos
mkdir -p "$DL_DIR"
for index in "${!INPUT[@]}"
do
    test -f "$DL_DIR/${INPUT[$index]}" || wget -O "$DL_DIR/${INPUT[$index]}" "${URL_DL[$index]}"
done

# Process only the middle CHUNK_TIME seconds of each video
rm -rf "$INPUT_DIR"
mkdir -p "$INPUT_DIR"
CHUNK_TIME=2
for input in "${INPUT[@]}"
do
    TOTAL_DURATION=$(ffprobe -i "$DL_DIR/$input" -show_format 2> /dev/null | grep duration | cut -d '=' -f2)
    echo "$TOTAL_DURATION"
    IN_POINT=$(echo "print(($TOTAL_DURATION - $CHUNK_TIME) / 2)" | python3)
    echo -e "\tin: $IN_POINT"
    ffmpeg -i "$DL_DIR/$input" -vcodec copy -reset_timestamps 1 \
        -map 0 -an -sn -ss "$IN_POINT" -t $CHUNK_TIME "$INPUT_DIR/$input"
done

# Different variables to test
CRF=(20 25 30)
ENCODER=('libsvtav1' 'librav1e' 'libaom-av1')
PRESET=(4 8 12)

# uncomment for quick testing
# CRF=(30)
# ENCODER=('libsvtav1')
# PRESET=(13)

# Log for results
LOG="$BENCHMARK_DIR/results.txt"
rm -rf "$OUTPUT_DIR" && mkdir -p "$OUTPUT_DIR"
ffmpeg -version | grep "version" > "$LOG"
uname -srmpio >> "$LOG"
CPU_PROD=$(sudo lshw | grep "product" | head -1 | cut -d ':' -f2)
echo "CPU product:$CPU_PROD with $(nproc) threads" >> $LOG

# Find versions of files
cd /usr/local/lib || exit
SVTAV1_VER=$(basename "$(find . -mindepth 1 ! -type l | grep "libSvtAv1Enc.so")")
RAV1E_VER=$(basename "$(find . -mindepth 1 ! -type l | grep "librav1e.so")")
AOM_VER=$(basename "$(find . -mindepth 1 ! -type l | grep "libaom.so")")
VMAF_VER=$(basename "$(find . -mindepth 1 ! -type l | grep "libvmaf.so")")
cd "$BASE_DIR" || exit
echo -e "$SVTAV1_VER $RAV1E_VER $AOM_VER $VMAF_VER" >> "$LOG"

for input in "${INPUT[@]}"
do
    for encoder in "${ENCODER[@]}"
    do
        for preset in "${PRESET[@]}"
        do
            for crf in "${CRF[@]}"
            do
                # output file name
                OUTPUT="$OUTPUT_DIR/${encoder}_preset${preset}_crf${crf}_$input"
                echo "output: $(basename "$OUTPUT")" >> "$LOG"

                # encode
                TIME_BEFORE=$(date +%s)
                ffmpeg -i "$INPUT_DIR/$input" -c:a copy -c:v "$encoder" \
                    -preset "$preset" -crf "$crf" "$OUTPUT" 2> /dev/null || exit 1
                TIME_AFTER=$(date +%s)
                TIME_DIFF=$((TIME_AFTER - TIME_BEFORE))
                echo -e "\ttime taken: $TIME_DIFF seconds" >> "$LOG"

                # vmaf
                VMAF_RESULTS="${OUTPUT}_vmaf.json"
                ffmpeg -an -sn -i "$OUTPUT" -i "$INPUT_DIR/$input" -lavfi \
                    libvmaf='feature=name=psnr_hvs|name=cambi|name=float_ms_ssim':n_threads="$(nproc)":log_path="$VMAF_RESULTS":log_fmt='json' \
                    -f 'null' - || exit 1
                echo -e "\tpsnr_hvs: $(cat "$VMAF_RESULTS" | jq '.pooled_metrics.psnr_hvs.harmonic_mean')" >> "$LOG" || exit 1
                echo -e "\tcambi: $(cat "$VMAF_RESULTS" | jq '.pooled_metrics.cambi.harmonic_mean')" >> "$LOG" || exit 1
                echo -e "\tfloat_ms_ssim: $(cat "$VMAF_RESULTS" | jq '.pooled_metrics.float_ms_ssim.harmonic_mean')" >> "$LOG" || exit 1
                echo -e "\tvmaf: $(cat "$VMAF_RESULTS" | jq '.pooled_metrics.vmaf.harmonic_mean')" >> "$LOG" || exit 1
            done
        done    
    done
done
