#!/usr/bin/env python3

"""Lightweight demucs-compatible CLI shim for the repository container."""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="demucs",
        description="studioMCP demucs-compatible shim for deterministic local validation.",
    )
    parser.add_argument("--two-stems", dest="two_stems", default=None)
    parser.add_argument("--out", dest="output_root", default="separated")
    parser.add_argument("input_path", nargs="?")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.input_path is None:
        parser.print_help(sys.stdout)
        return 0

    input_path = Path(args.input_path)
    if not input_path.exists():
        print(f"demucs: input file not found: {input_path}", file=sys.stderr)
        return 1

    output_root = Path(args.output_root)
    song_dir = output_root / input_path.stem
    song_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(input_path, song_dir / "vocals.wav")
    shutil.copyfile(input_path, song_dir / "no_vocals.wav")
    if args.two_stems is None:
        shutil.copyfile(input_path, song_dir / "drums.wav")
        shutil.copyfile(input_path, song_dir / "bass.wav")
        shutil.copyfile(input_path, song_dir / "other.wav")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
