#!/usr/bin/env bash

# this is simply my recommended encoding method.
# do not take this as a holy grail.

# global path variables
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "$(basename "$0") -i input_file [options] "
    echo -e "\t[-p] print the command instead of executing it"
    echo -e "\t[-c] use cropdetect"
    echo -e "\t[-s] use same container as input, default is mkv"
    echo -e "\t[-v] Print relevant version info"
    echo -e "\t[-g NUM] set film grain for encode"
    echo -e "\t[-P NUM] override default preset (3)"
    echo -e "\n\t[output_file] if not set, will create at $HOME/"
    echo -e "\n\t[-I] Install this as /usr/local/bin/encode"
    echo -e "\t[-U] Uninstall this from /usr/local/bin/encode"
    return 0 
}

get_duration() {
    ffmpeg -i "$1" 2>&1 | grep "Duration" | awk '{print $2}' | tr -d ,
}

get_crop() {
    local DURATION="$(get_duration "$INPUT")"
    local TOTAL_SECONDS="$(echo "$DURATION" | awk -F: '{ print ($1 * 3600) + ($2 * 60) + $3 }')"
    # get cropdetect value for first 1/5 of input
    local TIME_ENC="$(echo "$TOTAL_SECONDS / 2" | bc)"
    ffmpeg -hide_banner -ss 0 -discard 'nokey' -i "$INPUT" -t "$TIME_ENC" \
        -map '0:v:0' -filter:v:0 'cropdetect=limit=100:round=16:skip=2:reset_count=0' \
        -codec:v 'wrapped_avframe' -f 'null' '/dev/null' -y 2>&1 | grep -o crop=.* \
        | sort -bh | uniq -c | sort -bh | tail -n1 | grep -o "crop=.*"
}

unmap_streams(){
    local INPUT="$1"
    local UNMAP_FILTER="bin_data|jpeg|png"
    local UNMAP_STREAMS=$(ffprobe "$INPUT" 2>&1 | grep "Stream" | grep -Ei "$UNMAP_FILTER" | cut -d':' -f2 | cut -d'[' -f1 | tr '\n' ' ')
    local UNMAP_CMD=""
    for UNMAP_STREAM in $UNMAP_STREAMS; do
        UNMAP_CMD+="-map -0:$UNMAP_STREAM "
    done
    echo "$UNMAP_CMD"
}

get_bitrate_audio() {
    local BITRATE_CMD=""
    NUM_AUDIO_STREAMS=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$INPUT" | wc -l)
    for ((i = 0; i < NUM_AUDIO_STREAMS; i++)); do
        NUM_CHANNELS=$(ffprobe -v error -select_streams "a:$i" -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$INPUT")
        BITRATE=$((NUM_CHANNELS * 64))
        CODEC_NAME="$(ffprobe -v error -select_streams "a:$i" -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT")"
        # don't encode opus streams
        if [[ "$CODEC_NAME" == 'opus' ]]; then
            BITRATE_CMD+="-c:a:$i copy "
        else
            BITRATE_CMD+="-filter:a:$i aformat=channel_layouts=7.1|5.1|stereo|mono -c:a:$i libopus -b:a:$i ${BITRATE}k "
        fi
    done
    echo "$BITRATE_CMD"
}

convert_subs() {
    local SUB_CONVERT_CMD=""
    NUM_SUBTITLE_STREAMS=$(ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$INPUT" | wc -l)
    for ((i = 0; i < NUM_SUBTITLE_STREAMS; i++)); do
        SUBTITLE_FORMAT=$(ffprobe -v error -select_streams "s:$i" -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT")
        test "$SUBTITLE_FORMAT" == "eia_608" && SUB_CONVERT_CMD+="-c:s:$i srt "
    done
    echo "$SUB_CONVERT_CMD"
}

ffmpeg_version() {
    ffmpeg -version 2>&1 | head -n 1 | grep version | cut -d' ' -f1-3
}

video_enc_version() {
    SvtAv1EncApp --version | head -n 1
}

audio_enc_version() {
    local AUDIO_ENC_VERSION
    if command -v ldd > /dev/null ; then
        AUDIO_ENC_VERSION="$(ldd "$(which ffmpeg)" | grep -i libopus | cut -d' ' -f3 | xargs readlink)"
    elif command -v otool > /dev/null ; then
        AUDIO_ENC_VERSION="$(otool -L $(which ffmpeg) | grep libopus | tr -d ')' | awk -F' ' '{print $NF}')"
    fi
    local AUDIO_ENC_GIT="$(cd "$BUILDER_DIR/repos/opus" && git rev-parse --short HEAD)"
    test "$AUDIO_ENC_GIT" != '' && AUDIO_ENC_VERSION+="-g${AUDIO_ENC_GIT}"
    echo "$AUDIO_ENC_VERSION"
    
}

encode() {
    ENCODE_FILE="/tmp/$(basename "$OUTPUT")_encode.sh"
    echo -e '#!/usr/bin/env bash\n' > "$ENCODE_FILE"
    echo "export OUTPUT=\"$OUTPUT\"" >> "$ENCODE_FILE"

    SVT_PARAMS="${GRAIN}sharpness=3:spy-rd=1:psy-rd=1:tune=3:enable-overlays=1:scd=1:fast-decode=1:enable-variance-boost=1:enable-qm=1:qm-min=0:qm-max=15"
    echo "export SVT_PARAMS=\"$SVT_PARAMS\"" >> "$ENCODE_FILE"

    UNMAP=$(unmap_streams "$INPUT")
    echo "export UNMAP=\"$UNMAP\"" >> "$ENCODE_FILE"

    # AUDIO_FORMAT='-af aformat=channel_layouts=7.1|5.1|stereo|mono'
    # echo "export AUDIO_FORMAT='$AUDIO_FORMAT'" >> "$ENCODE_FILE"
    
    AUDIO_BITRATE=$(get_bitrate_audio "$INPUT")
    echo "export AUDIO_BITRATE=\"$AUDIO_BITRATE\"" >> "$ENCODE_FILE"

    VIDEO_ENCODER="libsvtav1"
    echo "export VIDEO_ENCODER=\"$VIDEO_ENCODER\"" >> "$ENCODE_FILE"

    if [[ "$CROP" == "true" ]]; then
        VIDEO_CROP="-vf \"$(get_crop)\""
        echo "export VIDEO_CROP=\"$VIDEO_CROP\"" >> "$ENCODE_FILE"
    fi

    VIDEO_PARAMS="-pix_fmt yuv420p10le -crf 25 -preset $PRESET -g 240"
    echo "export VIDEO_PARAMS=\"$VIDEO_PARAMS\"" >> "$ENCODE_FILE"

    CONVERT_SUBS="$(convert_subs)"
    echo "export CONVERT_SUBS=\"$CONVERT_SUBS\"" >> "$ENCODE_FILE"

    FFMPEG_PARAMS="-y -c:s copy \$CONVERT_SUBS -c:V \$VIDEO_ENCODER \$VIDEO_PARAMS"
    echo "export FFMPEG_PARAMS=\"$FFMPEG_PARAMS\"" >> "$ENCODE_FILE"

    FFMPEG_VERSION="ffmpeg_version=$(ffmpeg_version)"
    echo "export FFMPEG_VERSION=\"$FFMPEG_VERSION\"" >> "$ENCODE_FILE"

    VIDEO_ENC_VERSION="video_encoder=$(video_enc_version)"
    echo "export VIDEO_ENC_VERSION=\"$VIDEO_ENC_VERSION\"" >> "$ENCODE_FILE"

    AUDIO_ENC_VERSION="audio_encoder=$(audio_enc_version)"
    echo "export AUDIO_ENC_VERSION=\"$AUDIO_ENC_VERSION\"" >> "$ENCODE_FILE"

    ADD_METADATA="\"encoding_params=\$VIDEO_PARAMS \$SVT_PARAMS\""
    echo "export ADD_METADATA=$ADD_METADATA" >> "$ENCODE_FILE"
    
    NL=' \\\n\t'
    echo >> "$ENCODE_FILE"

    echo -e ffmpeg -i \""$INPUT"\" $NL \
        -map 0 \$UNMAP \$VIDEO_CROP \
        \$AUDIO_FORMAT \$AUDIO_BITRATE $NL \
        -metadata \"\$FFMPEG_VERSION\" \
        -metadata \"\$VIDEO_ENC_VERSION\" $NL \
        -metadata \"\$AUDIO_ENC_VERSION\" \
        -metadata \"\$ADD_METADATA\" $NL \
        \$FFMPEG_PARAMS -dolbyvision 1 -svtav1-params \
        $NL \"\$SVT_PARAMS\" \"\$OUTPUT\" "||" $NL \
        ffmpeg -i \""$INPUT"\" $NL \
        -map 0 \$UNMAP \$VIDEO_CROP \
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

OPTS='vi:pcsg:P:IU'
NUM_OPTS="${#OPTS}"
# default values
CROP='false'
PRINT_OUT="false"
SAME_CONTAINER="false"
GRAIN=""
PRESET=3
# only using -I/U
MIN_OPT=1
# using all + output name
MAX_OPT=$(( NUM_OPTS + 1 ))
test "$#" -lt $MIN_OPT && echo "not enough arguments" && usage && exit 1
test "$#" -gt $MAX_OPT && echo "too many arguments" && usage && exit 1
OPTS_USED=0
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
        v)
            SCRIPT_VER="$(cd "$BUILDER_DIR" && git rev-parse --short HEAD)"
            FFMPEG_VER="$(ffmpeg_version)"
            SVTAV1_VER="$(video_enc_version)"
            LIBOPUS_VER="$(audio_enc_version)"
            echo "encode version: $SCRIPT_VER"
            echo "ffmpeg version: $FFMPEG_VER"
            echo "svtav1 version: $SVTAV1_VER"
            echo "libopus version: $LIBOPUS_VER"
            exit 0
            ;;
        i)
            if [[ $# -lt 2 ]]; then            
                echo "wrong arguments given"
                usage
                exit 1
            fi
            INPUT="${OPTARG}"
            OPTS_USED=$((OPTS_USED + 2))
            ;;
        p)
            PRINT_OUT="true"
            OPTS_USED=$((OPTS_USED + 1))
            ;;
        c)
            CROP="true"
            OPTS_USED=$((OPTS_USED + 1))
            ;;
        s)
            SAME_CONTAINER="true"
            OPTS_USED=$((OPTS_USED + 1))
            ;;
        g)
            if [[ ${OPTARG} != ?(-)+([[:digit:]]) || ${OPTARG} -lt 0 ]]; then
                echo "${OPTARG} is not a positive integer"
                usage
                exit 1
            fi
            GRAIN="film-grain=${OPTARG}:film-grain-denoise=1:adaptive-film-grain=1:"
            OPTS_USED=$((OPTS_USED + 2))
            ;;
        P)
            if [[ ${OPTARG} != ?(-)+([[:digit:]]) || ${OPTARG} -lt 0 ]]; then
                echo "${OPTARG} is not a positive integer"
                usage
                exit 1
            fi
            PRESET="${OPTARG}"
            OPTS_USED=$((OPTS_USED + 2))
            ;;
        *)
            echo "wrong flags given"
            usage
            exit 1
            ;;        
    esac
done

# allow optional output filename
if [[ $(($# - OPTS_USED)) == 1 ]]; then
    OUTPUT="${*: -1}"
else
    OUTPUT="${HOME}/av1_${INPUT}"
fi

# use same container for output
if [[ "$SAME_CONTAINER" == "true" ]]; then

    INP_FORMAT="$(mediainfo --Output="General;%Format%" "$INPUT")"
    EXT=""
    if [[ "$INP_FORMAT" == 'MPEG-4' ]]; then
        EXT='mp4'
    elif [[ "$INP_FORMAT" == 'Matroska' ]]; then
        EXT='mkv'
    else
        echo "unrecognized input format"
        exit 1
    fi
    OUTPUT="${OUTPUT%.*}"
    OUTPUT+=".${EXT}"
else
    EXT="mkv"
    OUTPUT="${OUTPUT%.*}"
    OUTPUT+=".${EXT}"
fi

echo
echo "INPUT: $INPUT, PRINT_OUT: $PRINT_OUT, GRAIN: $GRAIN, OUTPUT: $OUTPUT"
echo
encode
