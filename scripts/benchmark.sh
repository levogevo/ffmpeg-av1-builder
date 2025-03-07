#!/usr/bin/env bash

has_encoder() {
    CHECK_ENC="$1"
    HAS_ENC=$(ffmpeg -encoders 2>&1 | grep "$CHECK_ENC" | grep -v "configuration" > /dev/null; echo $?)
    return $HAS_ENC
}

BASE_DIR=$(pwd)
BENCHMARK_DIR="$BASE_DIR/benchmark"
DL_DIR="$BENCHMARK_DIR/downloads"
INPUT_DIR="$BENCHMARK_DIR/input"
OUTPUT_DIR="$BENCHMARK_DIR/output"

# input names and respective URLs
INPUT[0]='cosmos_laundromat.mp4'
URL_DL[0]='http://download.opencontent.netflix.com.s3.amazonaws.com/CosmosLaundromat/CosmosLaundromat_2k24p_HDR_P3PQ.mp4'
INPUT[1]='carnival_ride.mp4'
URL_DL[1]='https://www.pexels.com/download/video/19026924/?fps=25.0&h=2160&w=4096'
INPUT[2]='gpac_chimera.mp4'
URL_DL[2]='http://download.opencontent.netflix.com.s3.amazonaws.com/gpac/GPAC_Chimera_AVCMain_AACLC_10s.mp4'
INPUT[3]='B_1.mp4'
URL_DL[3]='http://download.opencontent.netflix.com.s3.amazonaws.com/AV1/DVB-DASH/B_1.mp4'
INPUT[4]='D_2.mp4'
URL_DL[4]='http://download.opencontent.netflix.com.s3.amazonaws.com/AV1/DVB-DASH/D_2.mp4'

# check for libvmaf
if [[ "$(ffmpeg 2>&1 | grep 'enable-libvmaf' ; echo $?)" == 1 ]]; then
    echo "libvmaf not found"
    echo "add -v flag to build.sh"
    exit 1
fi

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
    ffmpeg -ss "$IN_POINT" -i "$DL_DIR/$input" -vcodec copy -reset_timestamps 1 \
        -map 0 -an -sn  -t $CHUNK_TIME "$INPUT_DIR/$input"
done

THREADS="$(nproc)"

# Different variables to test
CRF=(20 25 30)
ENCODER=('librav1e' 'libaom-av1' 'libsvtav1' 'libx264' 'libx265' 'libvpx-vp9')
PRESET=(2 4 6 8)

# uncomment for quick testing
CRF=(25)
# ENCODER=('libsvtav1')
PRESET=(8)

# Log for results
LOG="$BENCHMARK_DIR/results.txt"
CSV="$BENCHMARK_DIR/results.csv"
rm -rf "$OUTPUT_DIR" && mkdir -p "$OUTPUT_DIR"
ffmpeg -version | grep -E "version|built|configuration" | fold -s -w 90 > "$LOG"
echo "ENCODER,PRESET,CRF,INPUT,TIME_TAKEN,SIZE,PSNR_HVS,CAMBI,FLOAT_MS_SSIM,VMAF" > "$CSV"
uname -srmpio >> "$LOG"
CPU_PROD=$(sudo lshw | grep "product" | head -1 | cut -d ':' -f2)
echo "CPU product:$CPU_PROD with $THREADS threads" >> $LOG

# Find versions of libs
LDD_TEXT="$BENCHMARK_DIR/ldd.txt"
ldd $(which ffmpeg) > "$LDD_TEXT"
get_version() {
    cat "$LDD_TEXT" | grep "$1" | cut -d' ' -f3 | xargs readlink
}
LIBRARY_NAMES=("libSvtAv1Enc" "librav1e" "libaom" "libx265" \
    "libvmaf" "libdav1d" "librockchip_mpp" "libx264" "libvpx")
LIBRARY_VERSIONS=""
cd "$BASE_DIR" || exit
for LIBRARY in "${LIBRARY_NAMES[@]}"
do
    echo "$LIBRARY"
    LIBRARY_VERSIONS+="$(get_version "$LIBRARY") "
done
echo -e "$LIBRARY_VERSIONS" | fold -s -w 90 >> "$LOG"

power2() { echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; }
TILES=$(power2 "$THREADS")

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

                # lib specific params
                PARAMS=""
                if ! has_encoder "$encoder"; then
                    continue
                fi
                if [[ "$encoder" == "librav1e" ]]; then
                    test "$crf" -eq 20 && quantizer=50
                    test "$crf" -eq 25 && quantizer=100
                    test "$crf" -eq 30 && quantizer=150
                    PARAMS="-speed $preset -rav1e-params tiles=$TILES:threads=$THREADS:quantizer=$quantizer"
                elif [[ "$encoder" == "libaom-av1" ]]; then
                    PARAMS="-cpu-used $preset -row-mt 1 -threads $THREADS -crf $crf"
                elif [[ "$encoder" == "libsvtav1" ]]; then
                    PARAMS="-preset $preset -crf $crf -svtav1-params \
                            scd=1:tune=0:enable-overlays=1:fast-decode=1:enable-variance-boost=1"
                elif [[ ("$encoder" == "libx264") || ("$encoder" == "libx265") ]]; then
                    test "$preset" -eq 2 && preset=veryslow
                    test "$preset" -eq 4 && preset=slower
                    test "$preset" -eq 6 && preset=slower
                    test "$preset" -eq 8 && preset=slow
                    PARAMS="-preset $preset -crf $crf"
                elif [[ "$encoder" == "libvpx-vp9" ]]; then
                    test "$preset" -eq 2 && cpu_used=2
                    test "$preset" -eq 4 && cpu_used=3
                    test "$preset" -eq 6 && cpu_used=4
                    test "$preset" -eq 8 && cpu_used=5
                    PARAMS="-cpu-used $cpu_used -crf $crf -b:v 0 -row-mt 1 -deadline 0 -quality 0"
                else
                    PARAMS=""
                fi

                # encode
                export TIMEFORMAT=%R
                FFMPEG_CMD="ffmpeg -i $INPUT_DIR/$input -pix_fmt yuv420p10le -c:v $encoder $PARAMS $OUTPUT"
                (time $FFMPEG_CMD) |& tee "$BENCHMARK_DIR"/TIME
                TIME_DIFF="$(cat "$BENCHMARK_DIR"/TIME | tail -n 1)"
                rm "$BENCHMARK_DIR"/TIME
                echo -e "\ttime taken: $TIME_DIFF seconds" >> "$LOG"
                echo -e "\tsize: $(du -h "$OUTPUT" | cut -f1)" >> "$LOG"
                CSV_LINE="${encoder},${preset},${crf},${input},${TIME_DIFF},$(du "$OUTPUT" | cut -f1)"                

                # vmaf
                VMAF_RESULTS="${OUTPUT}_vmaf.json"
                ffmpeg -an -sn -i "$OUTPUT" -i "$INPUT_DIR/$input" -lavfi \
                    libvmaf='feature=name=psnr_hvs|name=cambi|name=float_ms_ssim':n_threads="$(nproc)":log_path="$VMAF_RESULTS":log_fmt='json' \
                    -f 'null' - || exit 1
                echo -e "\tpsnr_hvs: $(cat "$VMAF_RESULTS" | jq '.pooled_metrics.psnr_hvs.harmonic_mean')" >> "$LOG" || exit 1
                CSV_LINE="${CSV_LINE},$(cat "$VMAF_RESULTS" | jq '.pooled_metrics.psnr_hvs.harmonic_mean')"

                echo -e "\tcambi: $(cat "$VMAF_RESULTS" | jq '.pooled_metrics.cambi.harmonic_mean')" >> "$LOG" || exit 1
                CSV_LINE="${CSV_LINE},$(cat "$VMAF_RESULTS" | jq '.pooled_metrics.cambi.harmonic_mean')"

                echo -e "\tfloat_ms_ssim: $(cat "$VMAF_RESULTS" | jq '.pooled_metrics.float_ms_ssim.harmonic_mean')" >> "$LOG" || exit 1
                CSV_LINE="${CSV_LINE},$(cat "$VMAF_RESULTS" | jq '.pooled_metrics.float_ms_ssim.harmonic_mean')"

                echo -e "\tvmaf: $(cat "$VMAF_RESULTS" | jq '.pooled_metrics.vmaf.harmonic_mean')" >> "$LOG" || exit 1
                CSV_LINE="${CSV_LINE},$(cat "$VMAF_RESULTS" | jq '.pooled_metrics.vmaf.harmonic_mean')"
                echo "$CSV_LINE" >> "$CSV"

            done
        done    
    done
done

echo -e "\n\n--- Results CSV ---\n" >> "$LOG"
cat "$CSV" >> "$LOG"
