#!/bin/bash

# global variables
INPUT="bebop.mkv"
SEGMENTS=10
SEGMENT_TIME=3
DURATION="$(get_duration "$INPUT")"
TOTAL_SECONDS="$(echo "$DURATION" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')"
SEGMENT_DIR='/tmp/fg_segments'
SEGMENTS_LIST="$SEGMENT_DIR/segments_list.txt"
OUTPUT_CONCAT="$SEGMENT_DIR/concatenated.mkv"
TEST_MIN_GRAIN=0
TEST_MAX_GRAIN=30
GRAIN_STEP=5
GRAIN_LOG="grain_log.txt"

get_duration() {
    ffmpeg -i "$1" 2>&1 | grep "Duration" | awk '{print $2}' | tr -d ,
}

segment_video() {
    # set number of segments and start times
    SEGMENT_PERCENTAGE=$((100 / SEGMENTS))
    SEGMENT=$SEGMENT_PERCENTAGE
    START_TIMES=()
    while [[ $SEGMENT -lt 100 ]]
    do
        START_TIME="$(echo "$SEGMENT * $TOTAL_SECONDS / 100" | bc)"
        START_TIMES+=("$START_TIME")
        SEGMENT=$((SEGMENT + SEGMENT_PERCENTAGE))
    done    
        
    # split up video into segments based on start times
    rm -rf "$SEGMENT_DIR"
    mkdir -p "$SEGMENT_DIR"
    for INDEX in "${!START_TIMES[@]}"
    do
        # don't concatenate the last segment
        if [[ $((INDEX + 1)) == "${#START_TIMES[@]}" ]]; then
            break
        fi
        START_TIME="${START_TIMES[$INDEX]}"
        OUTPUT_SEGMENT="$SEGMENT_DIR/segment_$INDEX.mkv"
        echo "START_TIME: $START_TIME"
        ffmpeg -ss "$START_TIME" -i "$INPUT" \
            -hide_banner -loglevel error -t "$SEGMENT_TIME" \
            -map 0:0 -reset_timestamps 1 -c copy "$OUTPUT_SEGMENT"
        echo "file '$(basename "$OUTPUT_SEGMENT")'" >> "$SEGMENTS_LIST"
    done
    
    # ffmpeg -f concat -safe 0 -i "$SEGMENTS_LIST" -hide_banner -loglevel error -c copy "$OUTPUT_CONCAT"
}

encode_segments() {
    cd "$SEGMENT_DIR" || exit
    clear
    echo > "$GRAIN_LOG"
    for VIDEO in $(ls segment*.mkv)
    do
        echo "$VIDEO" >> "$GRAIN_LOG"
        for GRAIN in $(seq $TEST_MIN_GRAIN $GRAIN_STEP $TEST_MAX_GRAIN)
        do
            OUTPUT_VIDEO="encoded_$VIDEO"
            encode -i "$VIDEO" -g $GRAIN "$OUTPUT_VIDEO"
            BITRATE="$(mediainfo "$OUTPUT_VIDEO" | tr -s ' ' | grep 'Bit rate : ' | cut -d':' -f2)"
            echo -e "\tgrain: $GRAIN, bitrate:$BITRATE" >> "$GRAIN_LOG"
        done
        echo >> "$GRAIN_LOG"
    done

    clear
    cat "$GRAIN_LOG"
}
