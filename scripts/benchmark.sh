#!/bin/bash

BASE_DIR=$(pwd)
BENCHMARK_DIR="$BASE_DIR/benchmark"
INPUT_DIR="$BENCHMARK_DIR/input"
OUTPUT_DIR="$BENCHMARK_DIR/output"

# input names and respective URLs
INPUT[0]='Chimera.mkv'
URL_DL[0]='http://download.opencontent.netflix.com.s3.amazonaws.com/Chimera/Chimera_DCI4k5994p_HDR_P3PQ.mp4'
INPUT[1]='SolLevante.mov'
URL_DL[1]='http://download.opencontent.netflix.com.s3.amazonaws.com/SolLevante/hdr10/SolLevante_HDR10_r2020_ST2084_UHD_24fps_1000nit.mov'
INPUT[2]='CosmosLaundromat.mp4'
URL_DL[2]='http://download.opencontent.netflix.com.s3.amazonaws.com/CosmosLaundromat/CosmosLaundromat_2k24p_HDR_P3PQ.mp4'
INPUT[3]='SPARKS.mkv'
URL_DL[3]='http://download.opencontent.netflix.com.s3.amazonaws.com/sparks-mxf-tracks/20161103_1023_SPARKS_4K_P3_PQ_4000nits_DoVi.mxf'
INPUT[4]='Meridian.mkv'
URL_DL[4]='http://download.opencontent.netflix.com.s3.amazonaws.com/Meridian/Meridian_UHD4k5994_HDR_P3PQ.mp4'

# download videos into input directory
mkdir -p "$INPUT_DIR"
CHUNK_TIME=2
for index in "${!INPUT[@]}"
do
    test -f "$INPUT_DIR/${INPUT[$index]}" && continue
    TOTAL_DURATION=$(ffprobe -i "${URL_DL[$index]}" -show_format 2> /dev/null | grep duration | cut -d '=' -f2)
    echo "$TOTAL_DURATION"
    IN_POINT=$(echo "print(($TOTAL_DURATION - $CHUNK_TIME) / 2)" | python3)
    echo -e "\tin: $IN_POINT"
    ffmpeg -ss "$IN_POINT" -i "${URL_DL[$index]}" -vcodec copy -reset_timestamps 1 \
        -map 0 -an -sn  -t $CHUNK_TIME "$INPUT_DIR/${INPUT[$index]}" || exit 1
done

THREADS="$(nproc)"

# Different variables to test
CRF=(20 25 30)
ENCODER=('libsvtav1' 'librav1e' 'libaom-av1')
PRESET=(2 4 6 8)

# uncomment for quick testing
# CRF=(25)
# ENCODER=('libsvtav1')
# ENCODER=('librav1e')
# ENCODER=('libaom-av1')
# PRESET=(8)

# Log for results
LOG="$BENCHMARK_DIR/results.txt"
CSV="$BENCHMARK_DIR/results.csv"
rm -rf "$OUTPUT_DIR" && mkdir -p "$OUTPUT_DIR"
ffmpeg -version | grep "version" > "$LOG"
echo "ENCODER,PRESET,CRF,INPUT,TIME_TAKEN,SIZE,PSNR_HVS,CAMBI,FLOAT_MS_SSIM,VMAF" > "$CSV"
uname -srmpio >> "$LOG"
CPU_PROD=$(sudo lshw | grep "product" | head -1 | cut -d ':' -f2)
echo "CPU product:$CPU_PROD with $THREADS threads" >> $LOG

# Find versions of files
cd /usr/local/lib || exit
SVTAV1_VER=$(basename "$(find . -mindepth 1 ! -type l | grep "libSvtAv1Enc.so")")
RAV1E_VER=$(basename "$(find . -mindepth 1 ! -type l | grep "librav1e.so")")
AOM_VER=$(basename "$(find . -mindepth 1 ! -type l | grep "libaom.so")")
VMAF_VER=$(basename "$(find . -mindepth 1 ! -type l | grep "libvmaf.so")")
DAV1D_VER=$(basename "$(find . -mindepth 1 ! -type l | grep "libdav1d.so")")
cd "$BASE_DIR" || exit
echo -e "$SVTAV1_VER $RAV1E_VER $AOM_VER $VMAF_VER $DAV1D_VER" >> "$LOG"

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
                if [[ "$encoder" == "librav1e" ]]
                then
                    test "$crf" -eq 20 && quantizer=50
                    test "$crf" -eq 25 && quantizer=100
                    test "$crf" -eq 30 && quantizer=150
                    PARAMS="-speed $preset -rav1e-params tiles=$TILES:threads=$THREADS:quantizer=$quantizer"
                elif [[ "$encoder" == "libaom-av1" ]]
                then
                    PARAMS="-cpu-used $preset -row-mt 1 -threads $THREADS -crf $crf"
                elif [[ "$encoder" == "libsvtav1" ]]
                then
                    PARAMS="-preset $preset -crf $crf -svtav1-params \
                            scd=1:tune=0:enable-overlays=1:enable-hdr=1:fast-decode=1 "
                else
                    PARAMS=""
                fi

                # encode
                export TIMEFORMAT=%R
                FFMPEG_CMD="ffmpeg -i $INPUT_DIR/$input -c:a copy -c:v $encoder $PARAMS -pix_fmt yuv420p10le $OUTPUT"
                (time $FFMPEG_CMD) |& tee TIME
                TIME_DIFF="$(cat TIME | tail -n 1)"
                rm TIME
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
