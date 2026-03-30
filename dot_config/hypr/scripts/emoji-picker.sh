#!/usr/bin/env bash

set -euo pipefail

emoji_list() {
  python3 <<'PY'
import unicodedata as u

ranges = [
    (0x1F600, 0x1F64F),  # Emoticons
    (0x1F300, 0x1F5FF),  # Misc Symbols and Pictographs
    (0x1F680, 0x1F6FF),  # Transport and Map
    (0x1F900, 0x1F9FF),  # Supplemental Symbols and Pictographs
    (0x1FA70, 0x1FAFF),  # Symbols and Pictographs Extended-A
    (0x2600, 0x26FF),    # Misc symbols
    (0x2700, 0x27BF),    # Dingbats
]

skip_terms = (
    "CJK",
    "IDEOGRAPH",
    "VARIATION SELECTOR",
    "TAG ",
    "SURROGATE",
)

skip_codepoints = {
    0x200D,  # ZERO WIDTH JOINER
    0x20E3,  # COMBINING ENCLOSING KEYCAP
    0xFE0E,  # text presentation selector
    0xFE0F,  # emoji presentation selector
}

seen = set()

for start, end in ranges:
    for codepoint in range(start, end + 1):
        if codepoint in skip_codepoints:
            continue

        char = chr(codepoint)
        name = u.name(char, "")
        if not name or any(term in name for term in skip_terms):
            continue

        if char in seen:
            continue

        seen.add(char)
        print(f"{char} {name.lower()}")
PY
}

choice="$(
  emoji_list | wofi --dmenu --prompt 'Emoji' --insensitive
)"

if [[ -z "${choice}" ]]; then
  exit 0
fi

emoji="${choice%% *}"
printf '%s' "${emoji}" | wl-copy
notify-send "Emoji copied" "${emoji} copied to clipboard"
