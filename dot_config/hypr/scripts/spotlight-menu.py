#!/usr/bin/env python3

import configparser
import os
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path


APP_DIRS = (
    Path.home() / ".local/share/applications",
    Path("/usr/local/share/applications"),
    Path("/usr/share/applications"),
)

MAX_DISPLAY_LENGTH = 58


def run_detached(command: list[str]) -> None:
    subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().casefold())


def shorten_display(text: str, limit: int = MAX_DISPLAY_LENGTH) -> str:
    if len(text) <= limit:
        return text
    return text[: limit - 3].rstrip() + "..."


def desktop_display(entry: dict[str, str], duplicate_names: set[str]) -> str:
    display = entry["name"]
    if normalize(entry["name"]) in duplicate_names:
        display = f"{display}  [{entry['id']}]"
    return shorten_display(display)


def load_desktop_entries() -> tuple[list[str], dict[str, dict[str, str]], dict[str, dict[str, str]]]:
    seen_ids: set[str] = set()
    entries: list[dict[str, str]] = []
    name_counts: dict[str, int] = {}

    for directory in APP_DIRS:
        if not directory.is_dir():
            continue

        for path in sorted(directory.glob("*.desktop")):
            desktop_id = path.name
            if desktop_id in seen_ids:
                continue

            parser = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                parser.read(path, encoding="utf-8")
            except (configparser.Error, OSError, UnicodeDecodeError):
                continue

            if "Desktop Entry" not in parser:
                continue

            section = parser["Desktop Entry"]
            if section.get("Type", "") != "Application":
                continue
            if section.get("NoDisplay", "").lower() == "true":
                continue
            if section.get("Hidden", "").lower() == "true":
                continue

            name = section.get("Name", "").strip()
            if not name:
                continue

            seen_ids.add(desktop_id)
            entries.append({"id": desktop_id, "name": name})
            key = normalize(name)
            name_counts[key] = name_counts.get(key, 0) + 1

    duplicate_names = {name for name, count in name_counts.items() if count > 1}
    display_map: dict[str, dict[str, str]] = {}
    exact_name_map: dict[str, dict[str, str]] = {}
    displays: list[str] = []

    entries.sort(key=lambda item: item["name"].casefold())
    for entry in entries:
        display = desktop_display(entry, duplicate_names)
        display_map[display] = entry
        displays.append(display)
        exact_name_map.setdefault(normalize(entry["name"]), entry)

    return displays, display_map, exact_name_map


def build_options() -> tuple[list[str], dict[str, dict[str, str]], dict[str, dict[str, str]]]:
    app_displays, app_display_map, exact_name_map = load_desktop_entries()
    return app_displays, app_display_map, exact_name_map


def show_menu(options: list[str]) -> str:
    proc = subprocess.run(
        [
            "wofi",
            "--dmenu",
            "--insensitive",
            "--prompt",
            "search",
            "--matching",
            "contains",
            "--sort-order",
            "alphabetical",
            "--hide-scroll",
            "--width",
            "620",
        ],
        input="\n".join(options),
        text=True,
        capture_output=True,
    )

    if proc.returncode != 0:
        return ""

    return proc.stdout.strip()


def looks_like_url(query: str) -> bool:
    return bool(
        re.match(r"^(https?://|file://|ftp://)", query, flags=re.IGNORECASE)
        or re.match(r"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+([/?#:].*)?$", query)
    )


def open_target(target: str) -> None:
    run_detached(["xdg-open", target])


def binary_in_path(binary: str) -> str | None:
    for directory in os.environ.get("PATH", "").split(":"):
        candidate = Path(directory) / binary
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def handle_query(
    query: str,
    app_display_map: dict[str, dict[str, str]],
    exact_name_map: dict[str, dict[str, str]],
) -> int:
    if not query:
        return 0

    app_entry = app_display_map.get(query)
    if app_entry is None:
        app_entry = exact_name_map.get(normalize(query))

    if app_entry is not None:
        run_detached(["gtk-launch", app_entry["id"]])
        return 0

    if query.startswith(">"):
        command = query[1:].strip()
        if not command:
            return 1
        run_detached(["kitty", "sh", "-lc", command])
        return 0

    if query.startswith(("~", "/", "./", "../")):
        path = Path(query).expanduser()
        if path.exists():
            open_target(str(path))
            return 0

    if looks_like_url(query):
        target = query if "://" in query else f"https://{query}"
        open_target(target)
        return 0

    open_target(f"https://duckduckgo.com/?q={urllib.parse.quote_plus(query)}")
    return 0


def main() -> int:
    if not binary_in_path("wofi"):
        print("wofi is not installed", file=sys.stderr)
        return 1

    options, app_display_map, exact_name_map = build_options()
    query = show_menu(options)
    return handle_query(query, app_display_map, exact_name_map)


if __name__ == "__main__":
    raise SystemExit(main())
