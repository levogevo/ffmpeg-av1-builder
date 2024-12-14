#!/usr/bin/env bash

BASE_DIR=$(pwd)
RESULTS="$BASE_DIR/benchmark/results.csv"

gnuplot << EOF
set terminal pngcairo size 1920,1080
set output 'graphs/output_graph.png'
set title 'Video Metrics Comparison'
set xlabel 'CRF'
set ylabel 'SIZE'
set datafile separator ","

set style line 1 \
    linecolor rgb '#0060ad' \
    linetype 1 linewidth 2 \
    pointtype 7 pointsize 1.5

plot "$RESULTS" using "CRF":"SIZE" with points title 'PSNR HVS'
EOF

gnuplot << EOF
set terminal pngcairo enhanced font 'arial,10' size 800,600
set output 'graphs/line_graph.png'
set title 'Video Metrics Comparison'
set xlabel 'CRF'
set ylabel 'SIZE'
set datafile separator ","
set key autotitle columnhead
set grid

set style line 1 \
    linecolor rgb '#0060ad' \
    linetype 1 linewidth 2 \
    pointtype 7 pointsize 1.5

plot "$RESULTS" using 3:6 with linepoints linestyle 1
EOF
