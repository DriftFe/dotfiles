#!/usr/bin/env python3

import hashlib
import re
import subprocess
import tempfile
import time
from pathlib import Path


MAX_LABEL_LENGTH = 92
IMAGE_ENTRY_RE = re.compile(
    r"^\[\[ binary data (?P<size>.+?) (?P<kind>png|jpg|jpeg|webp|gif|bmp) (?P<dims>\d+x\d+) \]\]$",
    flags=re.IGNORECASE,
)
WOFI_IMAGE_MODE = "img"
WOFI_TEXT_MODE = "text"


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


def split_entry(entry: str) -> tuple[str | None, str]:
    parts = entry.split("\t", 1)
    if len(parts) == 2 and parts[0].isdigit():
        return parts[0], parts[1]
    return None, entry


def image_match(entry: str) -> re.Match[str] | None:
    _, payload = split_entry(entry)
    return IMAGE_ENTRY_RE.match(payload)


def entry_id(entry: str) -> str | None:
    return split_entry(entry)[0]


def preview_label(entry: str) -> str:
    entry_id, payload = split_entry(entry)
    match = IMAGE_ENTRY_RE.match(payload)
    if match is None:
        if entry_id is None:
            return shorten(payload)
        return shorten(f"{entry_id}  {payload}")

    kind = match.group("kind").upper()
    size = match.group("size")
    dims = match.group("dims")
    prefix = f"{entry_id}  " if entry_id is not None else ""
    return f"{prefix}Image  {dims}  {size}  {kind}"


def decode_entry(entry: str) -> bytes | None:
    decoded = subprocess.run(
        ["cliphist", "decode"],
        input=entry.encode(),
        capture_output=True,
        check=False,
    )
    if decoded.returncode != 0:
        return None
    return decoded.stdout


def thumbnail_path(root: Path, entry: str) -> Path:
    digest = hashlib.sha256(entry.encode()).hexdigest()
    suffix = ".png"
    match = image_match(entry)
    if match is not None:
        kind = match.group("kind").lower()
        suffix = ".jpg" if kind == "jpeg" else f".{kind}"
    return root / f"{digest}{suffix}"


def menu_row(label: str, icon_path: Path | None) -> str:
    if icon_path is None:
        return label
    return f"{WOFI_IMAGE_MODE}:{icon_path}:{WOFI_TEXT_MODE}:{label}"


def remove_restored_duplicate(original: str, original_bytes: bytes) -> None:
    original_history_id = entry_id(original)

    time.sleep(0.2)

    latest = subprocess.run(
        ["cliphist", "list"],
        text=True,
        capture_output=True,
        check=False,
    )
    if latest.returncode != 0:
        return

    newest = next((line for line in latest.stdout.splitlines() if line.strip()), "")
    newest_history_id = entry_id(newest)
    if not newest or not newest_history_id:
        return
    if newest_history_id == original_history_id:
        return

    newest_bytes = decode_entry(newest)
    if newest_bytes is None:
        return
    if newest_bytes != original_bytes:
        return

    subprocess.run(
        ["cliphist", "delete", newest_history_id],
        capture_output=True,
        check=False,
    )


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

    with tempfile.TemporaryDirectory(prefix="clipboard-menu-") as temp_dir:
        temp_root = Path(temp_dir)
        display_to_full: dict[str, str] = {}
        used: set[str] = set()
        displays: list[str] = []

        for line in lines:
            display = unique_display(preview_label(line), used)
            icon_path = None

            if image_match(line) is not None:
                image_bytes = decode_entry(line)
                if image_bytes:
                    icon_path = thumbnail_path(temp_root, line)
                    icon_path.write_bytes(image_bytes)

            display_to_full[display] = line
            displays.append(menu_row(display, icon_path))

        menu = subprocess.run(
            [
                "wofi",
                "--dmenu",
                "--prompt",
                "search",
                "--insensitive",
                "--hide-scroll",
                "--cache-file",
                "/dev/null",
                "--allow-images",
                "--parse-search",
                "-D",
                "dmenu-parse_action=true",
                "-D",
                "image_size=48",
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

        decoded = decode_entry(original)
        if decoded is None:
            return 1

        copied = subprocess.run(
            ["wl-copy"],
            input=decoded,
            check=False,
        )
        if copied.returncode == 0:
            remove_restored_duplicate(original, decoded)
        return copied.returncode


if __name__ == "__main__":
    raise SystemExit(main())
