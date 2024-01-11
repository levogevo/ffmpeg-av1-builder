#!/bin/bash

BASE_DIR=$(pwd)
BENCHMARK_DIR="$BASE_DIR/benchmark"
INPUT_DIR="$BENCHMARK_DIR/input"
OUTPUT_DIR="$BENCHMARK_DIR/output"

mkdir -p "$INPUT_DIR"
test -f "$INPUT_DIR/test.mp4" || wget -O "$INPUT_DIR/test.mp4" 'https://www.pexels.com/download/video/19022224/?fps=59.9401&h=2160&w=3840'

rm -rf "$OUTPUT_DIR" && mkdir -p "$OUTPUT_DIR"
