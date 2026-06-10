#!/usr/bin/env python3
"""Compatibility wrapper for the shell screenshot helper."""

from pathlib import Path
import os
import sys


def main() -> None:
    script = Path(__file__).with_suffix(".sh")
    os.execv(str(script), [str(script), *sys.argv[1:]])


if __name__ == "__main__":
    main()
