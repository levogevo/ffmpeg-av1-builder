#!/bin/bash

usage() {
    echo "estimate_fg.sh -i input_file [-l NUM] [-s NUM] [-h NUM] [-I] [-U]"
    echo -e "\t-l low value to use as minimum film-grain [optional]"
    echo -e "\t-s step value to use increment from low to high film-grain [optional]"
    echo -e "\t-h high value to use as maximum film-grain [optional]"
    echo -e "\t-I Install this as /usr/local/bin/estimate-film-grain [optional]"
    echo -e "\t-U Uninstall this from /usr/local/bin/estimate-film-grain [optional]"
    return 0 
}

check_not_negative_optarg() {
    OPTARG="$1"
    if [[ ${OPTARG} != ?(-)+([[:digit:]]) || ${OPTARG} -lt 0 ]]; then
        echo "${OPTARG} is not a positive integer"
        usage
        exit 1
    fi
}

echoerr() { echo -e "$@" 1>&2; }

OPTS='l:s:h:i:IU'
NUM_OPTS="${#OPTS}"
# only using -I or -U
MIN_OPT=1
# using all
MAX_OPT=$NUM_OPTS
test "$#" -lt "$MIN_OPT" && echo "not enough arguments" && usage && exit 1
test "$#" -gt "$MAX_OPT" && echo "too many arguments" && usage && exit 1
while getopts "$OPTS" flag; do
    case "${flag}" in
        I)
            echo "attempting install"
            sudo ln -sf "$(pwd)/scripts/estimate_fg.sh" \
                /usr/local/bin/estimate-film-grain || exit 1
            echo "succesfull install"
            exit 0
            ;;
        U)
            echo "attempting uninstall"
            sudo rm /usr/local/bin/estimate-film-grain || exit 1
            echo "succesfull uninstall"
            exit 0
            ;;
        i)
            if [[ "$#" -lt 2 ]]; then            
                echo "wrong arguments given"
                usage
                exit 1
            fi
            INPUT="${OPTARG}"
            ;;
        l)
            check_not_negative_optarg "${OPTARG}"
            LOW_GRAIN="${OPTARG}"
            ;;
        s)
            check_not_negative_optarg "${OPTARG}"
            STEP_GRAIN="${OPTARG}"
            ;;
        h)
            check_not_negative_optarg "${OPTARG}"
            HIGH_GRAIN="${OPTARG}"
            ;;
        *)
            echo "wrong flags given"
            usage
            exit 1
            ;;        
    esac
done

if [[ ! -f "$INPUT" ]]; then
    echo "file does not exist"
    exit 1
fi

# set default values
test ! -n "$LOW_GRAIN" && LOW_GRAIN=0
test ! -n "$STEP_GRAIN" && STEP_GRAIN=5
test ! -n "$HIGH_GRAIN" && HIGH_GRAIN=30

echo "Estimating film grain for $INPUT"
echo -e "\tTesting grain from $LOW_GRAIN-$HIGH_GRAIN with $STEP_GRAIN step increments" && sleep 2

# get time in seconds
get_duration() {
    ffmpeg -i "$1" 2>&1 | grep "Duration" | awk '{print $2}' | tr -d , \
        | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }'
}

get_avg_bitrate() {
    ffprobe -select_streams v:0 "$1" 2>&1 | grep " bitrate: " | cut -d' ' -f8
}

# check if test bitrate is within 12% of target bitrate
check_bitrate_bounds() {
    TEST_BITRATE="$1"
    TARGET_BITRATE="$2"
    TARGET_DELTA="$(echo "$TARGET_BITRATE * .12" | bc)"
    DIFF_BITRATE=$((TEST_BITRATE - TARGET_BITRATE))
    DIFF_BITRATE="$(echo ${DIFF_BITRATE#-})"
    echoerr "TEST_BITRATE:\t$TEST_BITRATE"
    echoerr "TARGET_BITRATE:\t$TARGET_BITRATE"
    echoerr "TARGET_DELTA:\t$TARGET_DELTA"
    echoerr "DIFF_BITRATE:\t$DIFF_BITRATE"
    if [[ "$DIFF_BITRATE" < "$TARGET_DELTA" ]]; then
        echo "pass"
    else
        echo "fail"
    fi
}

# global variables
SEGMENTS=15
SEGMENT_TIME=4
MAX_SEGMENTS=6
TOTAL_SECONDS="$(get_duration "$INPUT")"
INPUT_BITRATE="$(get_avg_bitrate "$INPUT")"
SEGMENT_DIR='/tmp/fg_segments'
SEGMENTS_LIST="$SEGMENT_DIR/segments_list.txt"
OUTPUT_CONCAT="$SEGMENT_DIR/concatenated.mkv"
GRAIN_LOG="grain_log.txt"

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
    NUM_SEGMENTS=0
    for INDEX in "${!START_TIMES[@]}"
    do
        # don't concatenate the last segment
        if [[ $((INDEX + 1)) == "${#START_TIMES[@]}" ]]; then
            break
        fi
        # only encode the max number of segments
        if [[ $NUM_SEGMENTS == "$MAX_SEGMENTS" ]]; then
            return 0
        fi
        START_TIME="${START_TIMES[$INDEX]}"
        OUTPUT_SEGMENT="$SEGMENT_DIR/segment_$INDEX.mkv"
        echo "START_TIME: $START_TIME"
        ffmpeg -ss "$START_TIME" -i "$INPUT" \
            -hide_banner -loglevel error -t "$SEGMENT_TIME" \
            -map 0:0 -reset_timestamps 1 -c copy "$OUTPUT_SEGMENT"
        OUTPUT_SEGMENT_BITRATE="$(get_avg_bitrate "$OUTPUT_SEGMENT")"
        echo "comparing: $OUTPUT_SEGMENT_BITRATE vs $INPUT_BITRATE"
        CHECK_BOUNDS="$(check_bitrate_bounds "$OUTPUT_SEGMENT_BITRATE" "$INPUT_BITRATE")"
        if [[ "$CHECK_BOUNDS" == "pass" ]]; then
            echo "$OUTPUT_SEGMENT is within bitrate bounds"
            echo "file '$(basename "$OUTPUT_SEGMENT")'" >> "$SEGMENTS_LIST"
            NUM_SEGMENTS=$((NUM_SEGMENTS + 1))
        else
            echo "$OUTPUT_SEGMENT is not within bitrate bounds"
            rm "$OUTPUT_SEGMENT"
        fi
    done
    
    # ffmpeg -f concat -safe 0 -i "$SEGMENTS_LIST" -hide_banner -loglevel error -c copy "$OUTPUT_CONCAT"
}

encode_segments() {
    cd "$SEGMENT_DIR" || exit
    mkdir ./encoded || exit
    echo > "$GRAIN_LOG"
    for VIDEO in $(ls segment*.mkv)
    do
        echo "$VIDEO" >> "$GRAIN_LOG"
        for GRAIN in $(seq $LOW_GRAIN $STEP_GRAIN $HIGH_GRAIN)
        do
            OUTPUT_VIDEO="encoded/encoded_$VIDEO"
            encode -i "$VIDEO" -g $GRAIN -c "false" "$OUTPUT_VIDEO"
            BITRATE="$(mediainfo "$OUTPUT_VIDEO" | tr -s ' ' | grep 'Bit rate : ' | cut -d':' -f2)"
            echo -e "\tgrain: $GRAIN, bitrate:$BITRATE" >> "$GRAIN_LOG"
        done
        echo >> "$GRAIN_LOG"
    done

    cat "$GRAIN_LOG"
}

get_avg_bitrate "$INPUT"
segment_video
encode_segments
