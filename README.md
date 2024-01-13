# ffmpeg-av1-builder

This repository is a simple collection of bash scripts that:

1. Install required dependencies using `./scripts/install_deps.sh`
2. Build and install ffmpeg from source using `./scripts/build.sh`
3. Benchmark the different encoders using `./scripts/benchmark.sh`

AV1 encode quality is tested against 5 different open source videos using libsvtav1, librav1e, and libaom.
Netflix's libvmaf is used to analyze quality of the encodes against the original files.

Output of the three scripts is in `./benchmark/results.txt` which contains the following values for each encode:

* the time taken
* psnr_hvs
* cambi
* float_ms_ssim
* vmaf