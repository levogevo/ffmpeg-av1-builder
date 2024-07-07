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

get_duration() {
    ffmpeg -i "$1" 2>&1 | grep "Duration" | awk '{print $2}' | tr -d ,
}

# global variables
SEGMENTS=8
SEGMENT_TIME=2
DURATION="$(get_duration "$INPUT")"
TOTAL_SECONDS="$(echo "$DURATION" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')"
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
    echo > "$GRAIN_LOG"
    for VIDEO in $(ls segment*.mkv)
    do
        echo "$VIDEO" >> "$GRAIN_LOG"
        for GRAIN in $(seq $LOW_GRAIN $STEP_GRAIN $HIGH_GRAIN)
        do
            OUTPUT_VIDEO="encoded_$VIDEO"
            encode -i "$VIDEO" -g $GRAIN -c "false" "$OUTPUT_VIDEO"
            BITRATE="$(mediainfo "$OUTPUT_VIDEO" | tr -s ' ' | grep 'Bit rate : ' | cut -d':' -f2)"
            echo -e "\tgrain: $GRAIN, bitrate:$BITRATE" >> "$GRAIN_LOG"
        done
        echo >> "$GRAIN_LOG"
    done

    cat "$GRAIN_LOG"
}

segment_video
encode_segments
