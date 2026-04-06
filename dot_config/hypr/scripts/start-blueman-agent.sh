#!/usr/bin/env sh

blueman-applet &
sleep 2
pkill -x blueman-tray 2>/dev/null
wait
