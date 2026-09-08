#!/usr/bin/env python3

import argparse
import json
import struct
import zlib
from pathlib import Path

WIDTH, HEIGHT = 1600, 1000
BACKGROUND = (250, 250, 247, 255)
INK = (18, 18, 18, 255)
MUTED = (145, 145, 138, 255)
PALE = (224, 224, 214, 255)
ACCENT = (55, 55, 52, 255)

FONT = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111",
    "3": "111001111001111", "4": "101101111001001", "5": "111100111001111",
    "6": "111100111101111", "7": "111001001001001", "8": "111101111101111",
    "9": "111101111001111", ".": "000000000000010", "%": "100001010100001",
    "M": "100111101101101", "B": "110101110101110", "C": "111100100100111",
    "H": "101101111101101", "D": "110101101101110", "/": "001001010100100",
    "P": "110101110100100", "U": "101101101101111", "S": "011100010001110",
    "E": "111100110100111", "N": "101111111111101", "O": "010101101101010",
    "R": "110101110101101", "A": "010101111101101", "V": "111100100100100",
    "G": "111100101101111", "T": "111010010010010", "F": "111100110100100",
    "L": "100100100100111", "I": "111010010010111", "Y": "101101010010010",
    "-": "000000111000000", " ": "000000000000000", ":": "000000010000010",
}


def put(pixels: bytearray, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    if 0 <= x < WIDTH and 0 <= y < HEIGHT:
        offset = (y * WIDTH + x) * 4
        pixels[offset:offset + 4] = bytes(color)


def rect(pixels: bytearray, x: int, y: int, width: int, height: int, color) -> None:
    for row in range(max(0, y), min(HEIGHT, y + height)):
        start = (row * WIDTH + max(0, x)) * 4
        end = (row * WIDTH + min(WIDTH, x + width)) * 4
        pixels[start:end] = bytes(color) * max(0, min(WIDTH, x + width) - max(0, x))


def text(pixels: bytearray, value: str, x: int, y: int, scale: int = 4, color=INK) -> None:
    cursor = x
    for character in value.upper():
        glyph = FONT.get(character, FONT[" "])
        for index, bit in enumerate(glyph):
            if bit == "1":
                rect(pixels, cursor + (index % 3) * scale, y + (index // 3) * scale, scale, scale, color)
        cursor += 4 * scale


def bar(pixels: bytearray, x: int, baseline: int, width: int, height: int, color) -> None:
    rect(pixels, x, baseline - height, width, height, color)
    rect(pixels, x, baseline - height, width, 5, INK)


def write_png(path: Path, pixels: bytearray) -> None:
    raw = b"".join(b"\x00" + pixels[row * WIDTH * 4:(row + 1) * WIDTH * 4] for row in range(HEIGHT))
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the HermesUsageMonitor performance hero chart.")
    parser.add_argument("--launch-baseline", type=Path, default=Path("scripts/launch-baseline.json"))
    parser.add_argument("--resource-baseline", type=Path, default=Path("scripts/resource-baseline.json"))
    parser.add_argument("--output", type=Path, default=Path("Screenshots/performance-hero.png"))
    args = parser.parse_args()
    launch = json.loads(args.launch_baseline.read_text(encoding="utf-8"))
    resource = json.loads(args.resource_baseline.read_text(encoding="utf-8"))
    pixels = bytearray(bytes(BACKGROUND) * (WIDTH * HEIGHT))
    text(pixels, "HERMES USAGE MONITOR", 100, 90, 7)
    text(pixels, "PERFORMANCE PROFILE", 100, 150, 4, MUTED)
    rect(pixels, 100, 220, 1400, 4, INK)
    panels = [(100, "COLD LAUNCH"), (570, "MEMORY"), (1040, "CPU")]
    for x, label in panels:
        text(pixels, label, x, 280, 4)
        rect(pixels, x, 340, 380, 5, PALE)
        first_label, second_label = ("MEDIAN", "P95") if label == "COLD LAUNCH" else ("CLOSED", "OPEN")
        text(pixels, first_label, x, 390, 3, MUTED)
        text(pixels, second_label, x + 205, 390, 3, MUTED)
    launch_values = [float(launch["medianMilliseconds"]), float(launch["p95Milliseconds"])]
    memory_values = [resource["aggregates"]["closed"]["memoryAverageMegabytes"], resource["aggregates"]["open"]["memoryAverageMegabytes"]]
    memory_peaks = [resource["aggregates"]["closed"]["memoryPeakMegabytes"], resource["aggregates"]["open"]["memoryPeakMegabytes"]]
    cpu_values = [resource["aggregates"]["closed"]["cpuAveragePercent"], resource["aggregates"]["open"]["cpuAveragePercent"]]
    for x, values, unit in [(100, launch_values, "MS"), (570, memory_values, "MB"), (1040, cpu_values, "%")]:
        maximum = max(values) or 1
        for index, value in enumerate(values):
            height = int(300 * value / maximum)
            bar(pixels, x + index * 205, 740, 120, max(8, height), INK if index == 1 else ACCENT)
            text(pixels, f"{value:.1f}{unit}", x + index * 205, 790, 4)
        rect(pixels, x, 740, 380, 4, INK)
    memory_maximum = max(memory_peaks) or 1
    for index, value in enumerate(memory_peaks):
        height = int(300 * value / memory_maximum)
        rect(pixels, 570 + index * 205, 740 - height, 120, 4, MUTED)
    text(pixels, "MEDIAN / P95", 100, 875, 3, MUTED)
    text(pixels, "AVERAGE FOOTPRINT", 570, 875, 3, MUTED)
    text(pixels, "AVERAGE PROCESS CPU", 1040, 875, 3, MUTED)
    text(pixels, f"PEAK {memory_peaks[0]:.1f}/{memory_peaks[1]:.1f} MB", 570, 930, 3, MUTED)
    rect(pixels, 1360, 55, 12, 80, INK)
    rect(pixels, 1400, 55, 12, 80, INK)
    rect(pixels, 1360, 89, 52, 12, INK)
    rect(pixels, 1450, 70, 10, 10, INK)
    rect(pixels, 1470, 60, 10, 10, INK)
    rect(pixels, 1490, 70, 10, 10, INK)
    rect(pixels, 1470, 80, 10, 10, INK)
    write_png(args.output, pixels)
    print(args.output)


if __name__ == "__main__":
    main()
