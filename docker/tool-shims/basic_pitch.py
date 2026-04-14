#!/usr/bin/env python3

"""Lightweight basic-pitch-compatible CLI shim for the repository container."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


MIDI_TEMPLATE = bytes(
    [
        0x4D,
        0x54,
        0x68,
        0x64,
        0x00,
        0x00,
        0x00,
        0x06,
        0x00,
        0x00,
        0x00,
        0x01,
        0x01,
        0xE0,
        0x4D,
        0x54,
        0x72,
        0x6B,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x00,
        0x90,
        0x3C,
        0x64,
        0x81,
        0x70,
        0x80,
        0x3C,
        0x40,
        0x00,
        0xFF,
        0x2F,
        0x00,
    ]
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="basic-pitch",
        description="studioMCP basic-pitch-compatible shim for deterministic local validation.",
    )
    parser.add_argument("output_dir", nargs="?")
    parser.add_argument("input_path", nargs="?")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.output_dir is None and args.input_path is None:
        parser.print_help(sys.stdout)
        return 0
    if args.output_dir is None or args.input_path is None:
        parser.error("expected <output_dir> <input_path>")

    input_path = Path(args.input_path)
    if not input_path.exists():
        print(f"basic-pitch: input file not found: {input_path}", file=sys.stderr)
        return 1

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{input_path.stem}_basic_pitch.mid"
    output_path.write_bytes(MIDI_TEMPLATE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
