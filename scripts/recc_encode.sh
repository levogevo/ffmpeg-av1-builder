#!/bin/bash

# this is simply my recommended encoding method.
# do not take this as a holy grail.

usage() {
    echo "encode -i input_file [-p true/false] [-g NUM] output_file"
    echo -e "\t-p print the command instead of executing it [optional]"
    echo -e "\t-g set film grain for encode [optional]"
    return 0 
}

encode() {
    ENCODE_FILE="/tmp/encode.sh"
    SVT_PARAMS="${GRAIN}tune=0:enable-overlays=1:scd=1:enable-hdr=1:fast-decode=1:enable-variance-boost=1:enable-qm=1:qm-min=0:qm-max=15"
    UNMAP=$(unmap_streams "$INPUT")
    AUDIO_FORMAT='-af "aformat=channel_layouts=7.1|5.1|stereo|mono" -c:a libopus'
    AUDIO_BITRATE=$(get_bitrate_audio "$INPUT")
    FFMPEG_PARAMS='-y -c:s copy -c:V libsvtav1 -pix_fmt yuv420p10le -crf 25 -preset 3 -g 240'
    NL=' \\\n\t'

    echo '#!/bin/bash' > "$ENCODE_FILE"
    echo -e ffmpeg -i \""$INPUT"\" -map 0 $UNMAP \
        $AUDIO_FORMAT $NL $AUDIO_BITRATE \
        "$FFMPEG_PARAMS" -dolbyvision 1 -svtav1-params \
        $NL "\"$SVT_PARAMS\" \"$OUTPUT\" ||" $NL \
        ffmpeg -i \""$INPUT"\" -map 0 $UNMAP \
        $AUDIO_FORMAT $NL $AUDIO_BITRATE \
        "$FFMPEG_PARAMS" -svtav1-params \
        $NL "\"$SVT_PARAMS\" \"$OUTPUT\"" >> "$ENCODE_FILE"        
    
    echo "mkvpropedit \"$OUTPUT\" --add-track-statistics-tags" >> "$ENCODE_FILE"
    echo "mkvpropedit \"$OUTPUT\" --edit info --set \"title=\"" >> "$ENCODE_FILE"

    if [[ "$PRINT_OUT" == "true" ]];
    then
        cat "$ENCODE_FILE"
    else
        bash "$ENCODE_FILE"
    fi
}

unmap_streams(){
    INPUT="$1"
    UNMAP_FILTER="jpeg|png"
    UNMAP_STREAMS=$(ffprobe "$INPUT" 2>&1 | grep "Stream" | grep -Ei "$UNMAP_FILTER" | cut -d':' -f2 | tr '\n' ' ')
    UNMAP_CMD=""
    for UNMAP_STREAM in $UNMAP_STREAMS; do
        UNMAP_CMD+="-map -0:$UNMAP_STREAM "
    done
    echo "$UNMAP_CMD"
}

get_bitrate_audio() {
    BITRATE_CMD=""
    NUM_AUDIO_STREAMS=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$INPUT" | wc -l)
    for ((i = 0; i < NUM_AUDIO_STREAMS; i++)); do
        NUM_CHANNELS=$(ffprobe -v error -select_streams "a:$i" -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$INPUT")
        BITRATE=$((NUM_CHANNELS * 64))
        BITRATE_CMD+="-b:a:$i ${BITRATE}k "
    done
    echo "$BITRATE_CMD"
}


OPTS='i:p:g:'
NUM_OPTS=$(echo $OPTS | tr ':' '\n' | wc -l)
PRINT_OUT="false"
GRAIN=""
# only using -i
MIN_OPT=2
# using all + output name
MAX_OPT=$(( NUM_OPTS * 2 - 1 ))
test "$#" -lt $MIN_OPT && echo "not enough arguments" && usage && exit 1
test "$#" -gt $MAX_OPT && echo "too many arguments" && usage && exit 1
while getopts "$OPTS" flag; do
    case "${flag}" in
        i)
            INPUT="${OPTARG}"
            ;;
        p)
            PRINT_OUT="${OPTARG}"
            if [[ "$PRINT_OUT" != "false" && "$PRINT_OUT" != "true" ]]; then
                echo "unrecognized argument for -p: $PRINT_OUT"
                usage
                exit 1
            fi
            ;;
        g)
            if [[ ${OPTARG} != ?(-)+([[:digit:]]) || ${OPTARG} -lt 0 ]]; then
                echo "${OPTARG} is not a positive integer"
                usage
                exit 1
            fi
            GRAIN="film-grain=${OPTARG}:"
            ;;
        *)
            echo "wrong flags given"
            usage
            exit 1
            ;;        
    esac
done

# allow optional output filename
if [[ "$#" -eq $MAX_OPT ]]; then
    OUTPUT="${@: -1}"
else
    OUTPUT="${HOME}/av1_${INPUT}"
fi

echo
echo "INPUT: $INPUT, PRINT_OUT: $PRINT_OUT, GRAIN: $GRAIN, OUTPUT: $OUTPUT"
echo
encode
