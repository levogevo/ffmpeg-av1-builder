#!/usr/bin/env bash

usage() {
    echo "$(basename "$0") -i input_file [options]"
    echo -e "\t[-o output_file] file to output results to"
    echo -e "\t[-l NUM] low value to use as minimum film-grain"
    echo -e "\t[-s NUM] step value to use increment from low to high film-grain"
    echo -e "\t[-h NUM] high value to use as maximum film-grain"
    echo -e "\t[-p] plot bitrates using gnuplot"
    echo -e "\n\t[-I] Install this as /usr/local/bin/estimate-film-grain"
    echo -e "\t[-U] Uninstall this from /usr/local/bin/estimate-film-grain"
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

OPTS='po:l:s:h:i:IU'
NUM_OPTS="${#OPTS}"
# only using -I or -U
MIN_OPT=1
# using all
MAX_OPT=$NUM_OPTS
CALLING_DIR="$(pwd)"
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
            if [[ ! -f "${OPTARG}" ]]; then            
                echo "${OPTARG} does not exist"
                usage
                exit 1
            fi
            INPUT="${OPTARG}"
            ;;
        o)
            OUTPUT_FILE="${OPTARG}"
            ;;
        p)
            PLOT='true'
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

# set default values
test ! -n "$LOW_GRAIN" && LOW_GRAIN=0
test ! -n "$STEP_GRAIN" && STEP_GRAIN=2
test ! -n "$HIGH_GRAIN" && HIGH_GRAIN=20

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
    TARGET_DELTA="$(echo "$TARGET_BITRATE * 1" | bc)"
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
SEGMENTS=30
SEGMENT_TIME=3
MAX_SEGMENTS=5
TOTAL_SECONDS="$(get_duration "$INPUT")"
# INPUT_BITRATE="$(get_avg_bitrate "$INPUT")"
CLEAN_INP_NAME="$(echo "$INPUT" | tr ' ' '.' | tr -d '{}[]+')"
SEGMENT_DIR="/tmp/${CLEAN_INP_NAME}/fg_segments"
SEGMENT_BITRATE_LIST="$SEGMENT_DIR/segment_bitrates.txt"
SEGMENTS_LIST="$SEGMENT_DIR/segments_list.txt"
# OUTPUT_CONCAT="$SEGMENT_DIR/concatenated.mkv"
OPTS_HASH="$(echo "${LOW_GRAIN}${STEP_GRAIN}${HIGH_GRAIN}" | sha256sum | tr -d ' ' | cut -d'-' -f1)"
GRAIN_LOG="$SEGMENT_DIR/grain_log-${OPTS_HASH}.txt"

segment_video() {
    # set number of segments and start times
    SEGMENT_PERCENTAGE=$(echo "100 / $SEGMENTS" | bc)
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
    echo > "$SEGMENT_BITRATE_LIST"
    for INDEX in "${!START_TIMES[@]}"
    do
        START_TIME="${START_TIMES[$INDEX]}"
        OUTPUT_SEGMENT="$SEGMENT_DIR/segment_${INDEX}.mkv"
        ffmpeg -ss "$START_TIME" -i "$INPUT" \
            -hide_banner -loglevel error -t "$SEGMENT_TIME" \
            -map 0:v -reset_timestamps 1 -c copy "$OUTPUT_SEGMENT"
        OUTPUT_SEGMENT_BITRATE="$(get_avg_bitrate "$OUTPUT_SEGMENT")"
        echo "$(get_avg_bitrate "$OUTPUT_SEGMENT"): $OUTPUT_SEGMENT" >> "$SEGMENT_BITRATE_LIST"
    done

    # remove all but the highest bitrate MAX_SEGMENTS
    mapfile -t KEEP_SEGMENTS< <(cat "$SEGMENT_BITRATE_LIST" | sort -nr | head -${MAX_SEGMENTS} | tr -d ' ' | cut -d':' -f2)
    for KEEP in "${KEEP_SEGMENTS[@]}"
    do
        mv "$KEEP" "${KEEP}.keep"
    done
    rm "$SEGMENT_DIR"/*.mkv
    for KEEP in "${KEEP_SEGMENTS[@]}"
    do
        mv "${KEEP}.keep" "$KEEP"
    done
    ls "$SEGMENT_DIR"
    
    # ffmpeg -f concat -safe 0 -i "$SEGMENTS_LIST" -hide_banner -loglevel error -c copy "$OUTPUT_CONCAT"
}

get_output_bitrate() {
    INPUT="$1"
    BPS="$(ffprobe "$INPUT" 2>&1 | grep BPS | grep -v 'TAGS' | tr -d ' ' | cut -d':' -f2)"
    echo "scale=3;$BPS / 1000000" | bc -l
}

encode_segments() {
    mkdir -p "$SEGMENT_DIR/encoded"
    echo > "$GRAIN_LOG"
    for VIDEO in $(ls "$SEGMENT_DIR"/segment_*.mkv)
    do
        echo "file: $VIDEO" >> "$GRAIN_LOG"
        for GRAIN in $(seq "$LOW_GRAIN" "$STEP_GRAIN" "$HIGH_GRAIN")
        do
            BASE_VID="$(basename "$VIDEO")"
            OUTPUT_VIDEO="$SEGMENT_DIR/encoded/encoded_${BASE_VID}"
            encode -i "$VIDEO" -g "$GRAIN" "$OUTPUT_VIDEO"
            BITRATE="$(get_output_bitrate "$OUTPUT_VIDEO")"
            echo -e "\tgrain: $GRAIN, bitrate: $BITRATE" >> "$GRAIN_LOG"
        done
        echo >> "$GRAIN_LOG"
    done

    test -n "$OUTPUT_FILE" && cp "$GRAIN_LOG" "$CALLING_DIR/$OUTPUT_FILE"
    less "$GRAIN_LOG"

}

plot() {
    mapfile -t FILES< <( grep "file:" "$GRAIN_LOG" | cut -d':' -f2 | tr -d ' ' | sort | uniq )
    mapfile -t GRAINS< <( grep "grain:" "$GRAIN_LOG" | cut -d':' -f2  | cut -d',' -f1 | tr -d ' ' | sort -Vu)
    declare -a BITRATE_SUMS=()

    for FILE in "${FILES[@]}"
    do
        # get grains for each file
        LINE_FILE="$(grep -n "$FILE" "$GRAIN_LOG" | cut -d':' -f1 )"
        START_GRAIN_LINE="$(echo "$LINE_FILE + 1" | bc)"
        END_GRAIN_LINE="$(echo "$LINE_FILE + ${#GRAINS[@]}" | bc)"
        GRAINS_FOR_FILE="$(sed -n "$START_GRAIN_LINE, $END_GRAIN_LINE p" "$GRAIN_LOG")"
        # set baseline bitrate value
        BASELINE_BITRATE="$(echo "$GRAINS_FOR_FILE" | tr -d ' ' | grep "grain:${GRAINS[0]}" | cut -d':' -f3)"
        # get sum of bitrate percentages
        for GRAIN in "${GRAINS[@]}"
        do
            COMPARE_BITRATE="$(echo "$GRAINS_FOR_FILE" | tr -d ' ' | grep -w "grain:$GRAIN" | cut -d':' -f3)"
            BITRATE_PERCENTAGE="$(echo "$COMPARE_BITRATE / $BASELINE_BITRATE" | bc -l)"
            # fix NULL BITRATE_SUM for first comparison
            test -n "${BITRATE_SUMS[$GRAIN]}" || BITRATE_SUMS["$GRAIN"]=0
            BITRATE_SUMS["$GRAIN"]="$(echo "$BITRATE_PERCENTAGE + ${BITRATE_SUMS[$GRAIN]}" | bc -l)" 
        done
    done

    # clear plot file
    PLOT="$SEGMENT_DIR/plot.dat"
    echo -n > "$PLOT"

    # set average bitrates per grain
    for GRAIN in "${GRAINS[@]}"
    do
        AVG_BITRATE="$(echo "${BITRATE_SUMS[$GRAIN]} / ${#FILES[@]}" | bc -l)"
        echo -e "$GRAIN\t$AVG_BITRATE" >> "$PLOT"
    done

    # set terminal size
    TERMINAL="$(tty)"
    COLUMNS=$(stty -a <"$TERMINAL" | grep -Po '(?<=columns )\d+')
    ROWS=$(stty -a <"$TERMINAL" | grep -Po '(?<=rows )\d+')

    # plot data
    gnuplot -p -e " \
    set terminal dumb size $COLUMNS, $ROWS; \
    set autoscale; \
    set style line 1 \
        linecolor rgb '#0060ad' \
        linetype 1 linewidth 2 \
        pointtype 7 pointsize 1.5; \
    plot '$PLOT' with linespoints linestyle 1
    " | less
}

test "$PLOT" == 'true' && test -f "$GRAIN_LOG" && \
    { plot ; exit $? ; }
get_avg_bitrate "$INPUT"
segment_video
encode_segments
test "$PLOT" == 'true' && test -f "$GRAIN_LOG" && \
    { plot ; }