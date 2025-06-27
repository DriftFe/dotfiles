#!/bin/bash

PIDFILE="/tmp/gpu-recorder.pid"
OUTFILE="$HOME/Videos/rec-$(date +%Y%m%d-%H%M%S).mp4"
SOURCE="alsa_output.pci-0000_00_1f.3.analog-stereo.monitor"

if [ -f "$PIDFILE" ]; then
    pkill -F "$PIDFILE"
    rm "$PIDFILE"
    notify-send "🎥 Screen Recording Stopped"
else
    gpu-screen-recorder -w screen \
        -o "$OUTFILE" \
        -a "$SOURCE" \
        -f 60 \
        -ab 128k \
        -encoder cpu &

    echo $! > "$PIDFILE"
    notify-send "🎥 Screen Recording Started"
fi
