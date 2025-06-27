#!/bin/bash
percentage=$(brightnessctl get)
max=$(brightnessctl max)
percent=$(( 100 * percentage / max ))
echo "{\"percentage\": $percent}"
