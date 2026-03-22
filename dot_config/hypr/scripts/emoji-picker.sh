#!/usr/bin/env bash

set -euo pipefail

choice="$(
  cat <<'EOF' | wofi --dmenu --prompt 'Emoji' --insensitive
😀 grinning face
😃 smiling face
😄 grinning eyes
😁 beaming face
😅 smiling sweat
😂 tears of joy
🤣 rolling on floor laughing
🙂 slightly smiling face
😉 winking face
😊 smiling face with blush
😍 heart eyes
🥰 smiling hearts
😘 blowing a kiss
😋 yummy face
😎 cool face
🤩 star-struck
🤔 thinking face
🤨 raised eyebrow
😐 neutral face
😶 face without mouth
🙄 rolling eyes
😏 smirking face
😴 sleeping face
🤤 drooling face
😭 loudly crying face
😤 huffing face
😡 angry face
🤯 exploding head
🥳 partying face
😇 angel face
🤗 hugging face
🫡 saluting face
🫠 melting face
🤝 handshake
🙏 folded hands
💪 flexed biceps
🫶 heart hands
👏 clapping hands
👍 thumbs up
👎 thumbs down
👌 OK hand
✌ peace sign
🤘 sign of the horns
👀 eyes
🫵 pointing at you
❤️ red heart
🩷 pink heart
🧡 orange heart
💛 yellow heart
💚 green heart
🩵 light blue heart
💙 blue heart
💜 purple heart
🖤 black heart
🤍 white heart
🤎 brown heart
💔 broken heart
✨ sparkles
🔥 fire
⭐ star
🌙 crescent moon
☀ sun
☁ cloud
⚡ lightning
🌈 rainbow
❄ snowflake
💥 collision
💯 hundred points
✔ check mark
✖ cross mark
✅ check box
❌ cross mark button
⚠ warning
🚀 rocket
🎉 party popper
🎊 confetti ball
🎵 musical note
🎮 game controller
💻 laptop
⌨ keyboard
🖱 mouse
📱 phone
📷 camera
📌 pushpin
📎 paperclip
📝 memo
📚 books
🔒 locked
🔓 unlocked
🔑 key
💡 light bulb
🛠 hammer and wrench
🧠 brain
☕ hot beverage
🍕 pizza
🍔 burger
🍟 fries
🍜 ramen
🍪 cookie
🧋 bubble tea
🐱 cat
🐶 dog
🦊 fox
🐸 frog
🌸 cherry blossom
🌹 rose
🍀 four leaf clover
EOF
)"

if [[ -z "${choice}" ]]; then
  exit 0
fi

emoji="${choice%% *}"
printf '%s' "${emoji}" | wl-copy
notify-send "Emoji copied" "${emoji} copied to clipboard"
