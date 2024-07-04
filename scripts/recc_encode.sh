#!/bin/bash

# this is simply my recommended encoding method.
# do not take this as a holy grail.

# global path variables
SCRIPT_PATH="$(readlink "$(which "$0")")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "encode -i input_file [-p true/false] [-g NUM] [output_file_name] [-I] [-U]"
    echo -e "\t-p print the command instead of executing it [optional]"
    echo -e "\t-g set film grain for encode [optional]"
    echo -e "\toutput_file_name if not set, will create at $HOME/ [optional]"
    echo -e "\t-I Install this as /usr/local/bin/encode [optional]"
    echo -e "\t-U Uninstall this from /usr/local/bin/encode [optional]"
    return 0 
}

encode() {
    ENCODE_FILE="/tmp/$(basename "$OUTPUT")_encode.sh"
    echo -e '#!/bin/bash\n' > "$ENCODE_FILE"
    echo "export OUTPUT=\"$OUTPUT\"" >> "$ENCODE_FILE"

    SVT_PARAMS="${GRAIN}sharpness=2:tune=3:enable-overlays=1:scd=1:enable-hdr=1:fast-decode=1:enable-variance-boost=1:enable-qm=1:qm-min=0:qm-max=15"
    echo "export SVT_PARAMS=\"$SVT_PARAMS\"" >> "$ENCODE_FILE"

    UNMAP=$(unmap_streams "$INPUT")
    echo "export UNMAP=\"$UNMAP\"" >> "$ENCODE_FILE"

    AUDIO_FORMAT='-af aformat=channel_layouts=7.1|5.1|stereo|mono -c:a libopus'
    echo "export AUDIO_FORMAT='$AUDIO_FORMAT'" >> "$ENCODE_FILE"
    
    AUDIO_BITRATE=$(get_bitrate_audio "$INPUT")
    echo "export AUDIO_BITRATE=\"$AUDIO_BITRATE\"" >> "$ENCODE_FILE"

    VIDEO_ENCODER="libsvtav1"
    echo "export VIDEO_ENCODER=\"$VIDEO_ENCODER\"" >> "$ENCODE_FILE"

    VIDEO_CROP="-vf \"$(ffmpeg -i "$INPUT" -t 1 -vf cropdetect -f null - 2>&1 | awk '/crop/ { print $NF }' | tail -1)\""
    echo "export VIDEO_CROP=\"$VIDEO_CROP\"" >> "$ENCODE_FILE"

    VIDEO_PARAMS="-pix_fmt yuv420p10le -crf 25 -preset 3 -g 240"
    echo "export VIDEO_PARAMS=\"$VIDEO_PARAMS\"" >> "$ENCODE_FILE"

    FFMPEG_PARAMS="-y -c:s copy -c:V \$VIDEO_ENCODER \$VIDEO_PARAMS"
    echo "export FFMPEG_PARAMS=\"$FFMPEG_PARAMS\"" >> "$ENCODE_FILE"

    FFMPEG_VERSION="ffmpeg_version=$(ffmpeg -version 2>&1 | grep version | cut -d' ' -f1-3)"
    echo "export FFMPEG_VERSION=\"$FFMPEG_VERSION\"" >> "$ENCODE_FILE"

    VIDEO_ENC_VERSION="video_encoder=$(SvtAv1EncApp --version | head -n 1)"
    echo "export VIDEO_ENC_VERSION=\"$VIDEO_ENC_VERSION\"" >> "$ENCODE_FILE"

    AUDIO_ENC_VERSION="audio_encoder=$(ldd $(which ffmpeg) | grep -i libopus | cut -d' ' -f3 | xargs readlink)"
    AUDIO_ENC_VERSION+="-g$(cd "$BUILDER_DIR/opus" && git rev-parse --short HEAD)"
    echo "export AUDIO_ENC_VERSION=\"$AUDIO_ENC_VERSION\"" >> "$ENCODE_FILE"

    ADD_METADATA="\"encoding_params=\$VIDEO_PARAMS \$SVT_PARAMS\""
    echo "export ADD_METADATA=$ADD_METADATA" >> "$ENCODE_FILE"
    
    NL=' \\\n\t'
    echo >> "$ENCODE_FILE"

    echo -e ffmpeg -i \""$INPUT"\" -map 0 \$UNMAP \
        \$VIDEO_CROP \
        \$AUDIO_FORMAT \$AUDIO_BITRATE $NL \
        -metadata \"\$FFMPEG_VERSION\" \
        -metadata \"\$VIDEO_ENC_VERSION\" $NL \
        -metadata \"\$AUDIO_ENC_VERSION\" \
        -metadata \"\$ADD_METADATA\" $NL \
        \$FFMPEG_PARAMS -dolbyvision 1 -svtav1-params \
        $NL \"\$SVT_PARAMS\" \"\$OUTPUT\" "||" $NL \
        ffmpeg -i \""$INPUT"\" -map 0 \$UNMAP \
        \$VIDEO_CROP \
        \$AUDIO_FORMAT \$AUDIO_BITRATE $NL \
        -metadata \"\$FFMPEG_VERSION\" \
        -metadata \"\$VIDEO_ENC_VERSION\" $NL \
        -metadata \"\$AUDIO_ENC_VERSION\" \
        -metadata \"\$ADD_METADATA\" $NL \
        "\$FFMPEG_PARAMS" -svtav1-params \
        $NL "\"\$SVT_PARAMS\" \"\$OUTPUT\" || exit 1 " >> "$ENCODE_FILE"        
    echo >> "$ENCODE_FILE"
    
    if [[ "$EXT" == "mkv" ]]; then
        echo "mkvpropedit \"$OUTPUT\" --add-track-statistics-tags" >> "$ENCODE_FILE"
        echo "mkvpropedit \"$OUTPUT\" --edit info --set \"title=\"" >> "$ENCODE_FILE"
    fi

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


OPTS='i:p:g:IU'
NUM_OPTS="${#OPTS}"
PRINT_OUT="false"
GRAIN=""
# only using -I/U
MIN_OPT=1
# using all + output name
MAX_OPT=$(( NUM_OPTS + 1 ))
test "$#" -lt $MIN_OPT && echo "not enough arguments" && usage && exit 1
test "$#" -gt $MAX_OPT && echo "too many arguments" && usage && exit 1
while getopts "$OPTS" flag; do
    case "${flag}" in
        I)
            echo "attempting install"
            sudo ln -sf "$(pwd)/scripts/recc_encode.sh" \
                /usr/local/bin/encode || exit 1
            echo "succesfull install"
            exit 0
            ;;
        U)
            echo "attempting uninstall"
            sudo rm /usr/local/bin/encode || exit 1
            echo "succesfull uninstall"
            exit 0
            ;;
        i)
            if [[ $# -lt 2 ]]; then            
                echo "wrong arguments given"
                usage
                exit 1
            fi
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
            GRAIN="film-grain=${OPTARG}:film-grain-denoise=1:adaptive-film-grain=1:"
            ;;
        *)
            echo "wrong flags given"
            usage
            exit 1
            ;;        
    esac
done

# allow optional output filename
if [[ $(($# % 2)) != 0 ]]; then
    OUTPUT="${@: -1}"
else
    OUTPUT="${HOME}/av1_${INPUT}"
fi

# always use same container for output
INP_FILENAME=$(basename -- "$INPUT")
EXT="${INP_FILENAME##*.}"
OUTPUT="${OUTPUT%.*}"
OUTPUT+=".${EXT}"

echo
echo "INPUT: $INPUT, PRINT_OUT: $PRINT_OUT, GRAIN: $GRAIN, OUTPUT: $OUTPUT"
echo
encode
