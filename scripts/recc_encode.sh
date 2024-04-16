#!/bin/bash

# this is simply my recommended encoding method.
# do not take this as a holy grail.

encode() {
    FILENAME="$1"
    OUTPUT_NAME=""
    # allow optional output filename
    if [[ -n "$2" ]];
    then
        OUTPUT_NAME="$2"
    else
        OUTPUT_NAME="${HOME}/av1_${FILENAME}"
    fi
    
    echo ffmpeg -i \""$FILENAME"\" -map 0 \
        -af '"aformat=channel_layouts=7.1|5.1|stereo|mono"' -c:a libopus $(get_bitrate_audio "$FILENAME") \
        -c:s copy -c:v libsvtav1 -pix_fmt yuv420p10le -crf 20 -preset 3 -g 240 \
        -svtav1-params \"tune=0:enable-overlays=1:scd=1:enable-hdr=1:fast-decode=1:enable-variance-boost=1\" \
        \""$OUTPUT_NAME"\"
}

get_bitrate_audio() {
    FILENAME="$1"
    bitrate_cmd=""
    num_streams=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$FILENAME" | wc -l)
    for ((i = 0; i < num_streams; i++)); do
        num_channels=$(ffprobe -v error -select_streams "a:$i" -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$FILENAME")
        bitrate=$((num_channels * 64))
        bitrate_cmd+="-b:a:$i ${bitrate}k "
    done
    echo "$bitrate_cmd"
}

encode "$@"
