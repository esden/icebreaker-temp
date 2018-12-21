#!/bin/bash

if [ "x$1" == "x" ]; then
	echo "provide input file"
	exit 1
fi

set -ev

ffmpeg -i $1 -filter_complex "[0]split=2[top][bot];[top]crop=1620:540:150:0,rotate=PI[top];[bot]crop=1620:540:150:540[bot];[top][bot]hstack" out.mp4
ffmpeg -i out.mp4 -vf "scale=384:64" -pix_fmt rgb565 -f rawvideo out.raw
