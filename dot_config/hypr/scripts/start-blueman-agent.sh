#!/usr/bin/env sh

if pgrep -x blueman-applet >/dev/null 2>&1; then
  exit 0
fi

exec blueman-applet
