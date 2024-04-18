#!/bin/bash

# this is simply my recommended encoding method.
# do not take this as a holy grail.

usage() {
    echo "unrecognized arguments, please retry"
    echo "encode -i input_file [-p] output_file"
    echo -e "\t-p print the command instead of executing [optional]"
    return 0 
}

encode() {
    echo ffmpeg -i \""$INPUT"\" -map 0 \
        -af '"aformat=channel_layouts=7.1|5.1|stereo|mono"' -c:a libopus $(get_bitrate_audio "$INPUT") \
        -c:s copy -c:V libsvtav1 -pix_fmt yuv420p10le -crf 25 -preset 3 -g 240 \
        -svtav1-params \"tune=0:enable-overlays=1:scd=1:enable-hdr=1:fast-decode=1:enable-variance-boost=1\" \
        \""$OUTPUT"\" > /tmp/encode.sh
    
        if [[ "$PRINT_OUT" == "true" ]];
        then
            cat /tmp/encode.sh
        else
            bash /tmp/encode.sh
        fi
}

unmap_streams(){
    INPUT="$1"
    num_video_streams=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$INPUT" | wc -l)
    for ((i = 0; i < num_video_streams; i++)); do
        ffprobe -v error -select_streams "v:$i" -of default=noprint_wrappers=1:nokey=1 "$INPUT"
        ffprobe -select_streams "v:0" -of default=noprint_wrappers=1:nokey=1 'first_20_DN.mkv'
        ffprobe -v error -select_streams v -show_entries stream=index:stream_tags=type -of csv=p=0 'first_20_DN.mkv'
    done
    echo "$num_video_streams"
}

get_bitrate_audio() {
    bitrate_cmd=""
    num_audio_streams=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$INPUT" | wc -l)
    for ((i = 0; i < num_audio_streams; i++)); do
        num_channels=$(ffprobe -v error -select_streams "a:$i" -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$INPUT")
        bitrate=$((num_channels * 64))
        bitrate_cmd+="-b:a:$i ${bitrate}k "
    done
    echo "$bitrate_cmd"
}


OPTS='i:p'
NUM_OPTS=$(echo $OPTS | tr ':' '\n' | wc -l)
PRINT_OUT="false"
MIN_OPT=2
MAX_OPT=4
test "$#" -lt $MIN_OPT && usage && exit 1
test "$#" -gt $MAX_OPT && usage && exit 1
while getopts "$OPTS" flag; do
    case "${flag}" in
        i)
            INPUT="${OPTARG}"
            ;;
        p)
            PRINT_OUT="true"
            ;;
        *)
            usage
            exit 1
            ;;        
    esac
done

# allow optional output filename
if [[ "$#" -eq $MAX_OPT ]]; then
    OUTPUT="${@: -1}"
elif [[ 
    ("$PRINT_OUT" == "true") &&
    ( "$#" -eq 3) 
    ]]; then
    OUTPUT="${HOME}/av1_${INPUT}"
elif [[ "$#" -eq 2 ]]; then
    OUTPUT="${HOME}/av1_${INPUT}"
else
    OUTPUT="${@: -1}"
fi

echo
echo "INPUT: $INPUT, PRINT_OUT: $PRINT_OUT, OUTPUT: $OUTPUT"
echo

encode

# encode "$@"
# unmap_streams "$@"
