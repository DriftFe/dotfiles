local mainMod = "SUPER"

local function run(command)
    return hl.dsp.exec_cmd(command)
end

local directions = {
    l = "left",
    r = "right",
    u = "up",
    d = "down",
}

---------------------
--  System Controls
---------------------

hl.bind(mainMod .. " + L", run("hyprlock"))
hl.bind("ALT + SUPER + S", run("systemctl suspend"))
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + G", run("~/.config/hypr/scripts/gaming-mode.sh toggle"))

------------------
--  Applications
------------------

hl.bind(mainMod .. " + T", run(terminal))
hl.bind(mainMod .. " + E", run(fileManager))
hl.bind(mainMod .. " + A", run(menu))
hl.bind(mainMod .. " + B", run("zen-browser"))
hl.bind(mainMod .. " + D", run("vesktop"))
hl.bind(mainMod .. " + K", run("kdenlive"))
hl.bind(mainMod .. " + P", run("powder"))
hl.bind(mainMod .. " + C", run("vscodium"))
hl.bind(mainMod .. " + CTRL + S", run("spotify"))
hl.bind(mainMod .. " + SHIFT + A", run("waydroid-toggle"))
hl.bind("SUPER + SHIFT + A", run("ai-chat"))

-----------------------
--  Window Management
-----------------------

hl.bind(mainMod .. " + SHIFT + Q", run("~/.config/hypr/scripts/kill-window.sh"))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + W", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = directions.l }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = directions.r }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = directions.u }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = directions.d }))

hl.bind("ALT + LEFT", hl.dsp.window.move({ direction = directions.l }))
hl.bind("ALT + RIGHT", hl.dsp.window.move({ direction = directions.r }))
hl.bind("ALT + UP", hl.dsp.window.move({ direction = directions.u }))
hl.bind("ALT + DOWN", hl.dsp.window.move({ direction = directions.d }))

----------------
--  Workspaces
----------------

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.window.move({ workspace = "e+0" }))
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.workspace.toggle_special("magic"))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

------------------------------
--  Mouse Window Management
------------------------------

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-------------
--  Extras
-------------

hl.bind(mainMod .. " + V", run("~/.config/hypr/scripts/clipboard-menu.py"))
hl.bind(mainMod .. " + period", run("~/.config/hypr/scripts/emoji-picker.sh"))
hl.bind(mainMod .. " + R", run("~/.config/hypr/scripts/toggle-signal-radar.sh"))
hl.bind("SUPER + F", run([[kitty -e zsh -c "cbonsai -l --seed=40 -i; exec zsh" & kitty -e zsh -c "cava; exec zsh"]]))

----------------
--  Screenshots
----------------

hl.bind("ALT + S", run("~/.config/hypr/scripts/screenshot-swappy.sh clip"))
hl.bind("CTRL + ALT + S", run("~/.config/hypr/scripts/screenshot-swappy.sh area-save"))
hl.bind("Print", run("~/.config/hypr/scripts/screenshot-swappy.sh screen-save"))
hl.bind("Escape", run("~/.config/hypr/scripts/screenshot-rescue.sh"), { non_consuming = true })
hl.bind("CTRL + ALT + Escape", run("~/.config/hypr/scripts/screenshot-rescue.sh"))

---------------------------
--  Audio and Brightness
---------------------------

hl.bind("XF86AudioRaiseVolume", run("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", run("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", run("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", run("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", run("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", run("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

--------------------
--  Media Controls
--------------------

hl.bind("XF86AudioNext", run("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", run("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", run("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", run("playerctl previous"), { locked = true })
