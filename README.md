# ffmpeg-av1-builder

## General
This repository is a simple collection of bash scripts. Scripts have only been tested using Debian/Ubuntu/Arch. If not using apt/pacman, your dependencies will need to be manually installed. With the scripts, you can:

1. Install required dependencies using `./scripts/install_deps.sh`
2. Build and install ffmpeg from source using `./scripts/build.sh`
3. Install an encoding script using `./scripts/recc_encode_install.sh -I`
4. Install a film-grain estimation script using `./scripts/estimate_fg.sh -I`
5. Benchmark the different encoders using `./scripts/benchmark.sh`

## Encode script
The installation of the encoding script creates a symlink to this repo's `./scripts/recc_encode.sh` so do NOT remove this repo or the functionality of `encode` will FAIL. The `encode` script is a very simple way to use SvtAv1-PSY for video and Opus for audio for encoding, which are arguably the most ideal encoders as of writing this. `encode` does the following:
 - Maps all streams except image streams (effectively no poster/image in the output)
 - Sets the audio bitrate at 64kbps per channel for each audio track
 - Formats the audio output channel layout correctly for Opus
 - Attempts to encode with Dolby Vision and encodes without if the attempt fails
 - Preset 3 and CRF 25 for for SvtAv1
 - Enables sane advanced parameters
 - Removes video stream title name from output
 - Adds track statistics for proper output video/audio bitrate reporting
Read the specifics in the actual file : `./scripts/recc_encode.sh`

```bash
encode -i input_file [-p] [-c] [-s] [-v] [-g NUM] [output_file_name] [-I] [-U]
        -p print the command instead of executing it
        -c use cropdetect
        -s use same container as input, default is mkv
        -g set film grain for encode
        -v Print relevant version info

        output_file_name if not set, will create at /home/lgevorgyan/

        -I Install this as /usr/local/bin/encode
        -U Uninstall this from /usr/local/bin/encode
```
Example usage: 
 - `encode -i input.mkv output.mkv` standard usage
 - `encode -i input.mkv -p true` prints out what it will do, does not start encoding
 - `encode -i input.mkv` no output filename will create an output video in your home folder (~/)
 - `encode -i input.mkv -g 20` will encode with film-grain synthesis=20 WITH denoising

## Estimate film grain script
The installation of the script creates a symlink to this repo's `./scripts/estimate_fg.sh` so do NOT remove this repo or the functionality of `estimate-film-grain` will FAIL. The `estimate-film-grain` script is a way to estimate the ideal film grain of a video by encoding it at different film grain values and observing at what point does a higher film grain value result in diminishing returns.
```bash
estimate_fg.sh -i input_file [-o output_file] [-l NUM] [-s NUM] [-h NUM] [-I] [-U]
        -o file to output results to
        -l low value to use as minimum film-grain
        -s step value to use increment from low to high film-grain
        -h high value to use as maximum film-grain
        -I Install this as /usr/local/bin/estimate-film-grain
        -U Uninstall this from /usr/local/bin/estimate-film-grain
```

## Benchmark script
AV1 encode quality is tested against 5 different open source videos using libsvtav1, librav1e, and libaom.
Netflix's libvmaf is used to analyze quality of the encodes against the original files.

Output after running `./scripts/benchmark.sh` is in `./benchmark/results.txt` which contains the following values for each encode:

* the time taken
* psnr_hvs
* cambi
* float_ms_ssim
* vmaf