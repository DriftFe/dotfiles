#!/usr/bin/env python3

import subprocess
import sys


MAX_LABEL_LENGTH = 92


def shorten(text: str) -> str:
    if len(text) <= MAX_LABEL_LENGTH:
        return text
    return text[: MAX_LABEL_LENGTH - 3].rstrip() + "..."


def unique_display(base: str, used: set[str]) -> str:
    if base not in used:
        used.add(base)
        return base

    index = 2
    while True:
        candidate = f"{base} [{index}]"
        if candidate not in used:
            used.add(candidate)
            return candidate
        index += 1


def main() -> int:
    history = subprocess.run(
        ["cliphist", "list"],
        text=True,
        capture_output=True,
        check=False,
    )
    if history.returncode != 0:
        return history.returncode

    lines = [line for line in history.stdout.splitlines() if line.strip()]
    if not lines:
        return 0

    display_to_full: dict[str, str] = {}
    used: set[str] = set()
    displays: list[str] = []

    for line in lines:
        display = unique_display(shorten(line), used)
        display_to_full[display] = line
        displays.append(display)

    menu = subprocess.run(
        [
            "wofi",
            "--dmenu",
            "--prompt",
            "search",
            "--insensitive",
            "--hide-scroll",
        ],
        input="\n".join(displays),
        text=True,
        capture_output=True,
        check=False,
    )
    if menu.returncode != 0:
        return 0

    selection = menu.stdout.strip()
    if not selection:
        return 0

    original = display_to_full.get(selection)
    if original is None:
        return 1

    decoded = subprocess.run(
        ["cliphist", "decode"],
        input=original,
        text=True,
        capture_output=True,
        check=False,
    )
    if decoded.returncode != 0:
        return decoded.returncode

    copied = subprocess.run(
        ["wl-copy"],
        input=decoded.stdout,
        text=True,
        check=False,
    )
    return copied.returncode


if __name__ == "__main__":
    raise SystemExit(main())
