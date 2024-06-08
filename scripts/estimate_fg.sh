#!/bin/bash

get_duration() {
    ffmpeg -i "$1" 2>&1 | grep "Duration" | awk '{print $2}' | tr -d ,
}

INPUT="bebop.mkv"

DURATION="$(get_duration "$INPUT")"
TOTAL_SECONDS="$(echo "$DURATION" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')"
echo "TOTAL_SECONDS: $TOTAL_SECONDS"

# set number of segments and start times
SEGMENTS=9
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
SEGMENT_TIME=1
SEGMENT_DIR='./tmp/fg_segments'
SEGMENTS_LIST="$SEGMENT_DIR/segments_list.txt"
OUTPUT_CONCAT="$SEGMENT_DIR/concatenated.mkv"
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
    ffmpeg -ss "$START_TIME" -i "$INPUT" -hide_banner -loglevel error -t "$SEGMENT_TIME" -map 0:0 -c copy "$OUTPUT_SEGMENT"
    echo "file '$(basename "$OUTPUT_SEGMENT")'" >> "$SEGMENTS_LIST"
done

ffmpeg -f concat -safe 0 -i "$SEGMENTS_LIST" -hide_banner -loglevel error -c copy "$OUTPUT_CONCAT"
