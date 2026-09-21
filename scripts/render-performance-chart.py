#!/usr/bin/env python3

import argparse
import html
import json
from pathlib import Path
from typing import Any

WIDTH, HEIGHT = 960, 560
BACKGROUND = "#111111"
CARD = "#1C1C1E"
PRIMARY = "#F5F5F5"
SECONDARY = "#8E8E93"
GREEN = "#7DFFB3"
BLUE = "#64D2FF"
YELLOW = "#FFD60A"


def read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise RuntimeError(f"baseline is missing: {path}")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"baseline is not an object: {path}")
    return value


def number(value: Any, label: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as error:
        raise RuntimeError(f"baseline field {label} is not numeric") from error
    if result < 0:
        raise RuntimeError(f"baseline field {label} is negative")
    return result


def text(value: str, x: int, y: int, *, size: int, color: str, anchor: str = "middle", weight: str = "400") -> str:
    return (
        f'<text x="{x}" y="{y}" text-anchor="{anchor}" fill="{color}" '
        f'font-family="SF Pro Text, Helvetica Neue, sans-serif" font-size="{size}" '
        f'font-weight="{weight}">{html.escape(value)}</text>'
    )


def card(x: int, title: str, metrics: list[tuple[str, str, str]]) -> str:
    parts = [f'<rect x="{x}" y="112" width="280" height="360" rx="20" fill="{CARD}"/>']
    parts.append(text(title, x + 140, 154, size=15, color=SECONDARY, weight="600"))
    for index, (label, value, color) in enumerate(metrics):
        y = 214 + index * 82
        parts.append(text(label, x + 140, y, size=13, color=SECONDARY))
        parts.append(text(value, x + 140, y + 38, size=26, color=color, weight="500"))
    return "\n  ".join(parts)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the HermesUsageMonitor performance profile.")
    parser.add_argument("--launch-baseline", type=Path, default=Path("scripts/launch-baseline.json"))
    parser.add_argument("--resource-baseline", type=Path, default=Path("scripts/resource-baseline.json"))
    parser.add_argument("--output", type=Path, default=Path("Screenshots/performance.svg"))
    args = parser.parse_args()

    launch = read_json(args.launch_baseline)
    resource = read_json(args.resource_baseline)
    aggregates = resource.get("aggregates")
    if not isinstance(aggregates, dict):
        raise RuntimeError("resource baseline has no aggregates")
    closed = aggregates.get("closed")
    opened = aggregates.get("open")
    if not isinstance(closed, dict) or not isinstance(opened, dict):
        raise RuntimeError("resource baseline must contain closed and open aggregates")

    launch_median = number(launch.get("medianMilliseconds"), "medianMilliseconds")
    launch_p95 = number(launch.get("p95Milliseconds"), "p95Milliseconds")

    def state_metrics(state: dict[str, Any]) -> list[tuple[str, str, str]]:
        return [
            ("Physical footprint · average", f"{number(state.get('memoryAverageMegabytes'), 'memoryAverageMegabytes'):.1f} MiB", BLUE),
            ("Physical footprint · peak", f"{number(state.get('memoryPeakMegabytes'), 'memoryPeakMegabytes'):.1f} MiB", BLUE),
            ("Process CPU · average", f"{number(state.get('cpuAveragePercent'), 'cpuAveragePercent'):.3f}%", GREEN),
        ]

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" role="img">
  <title>HermesUsageMonitor Release performance profile</title>
  <rect width="{WIDTH}" height="{HEIGHT}" rx="28" fill="{BACKGROUND}"/>
  {text("HermesUsageMonitor", WIDTH // 2, 48, size=20, color=PRIMARY, weight="600")}
  {text("Release performance profile", WIDTH // 2, 78, size=13, color=SECONDARY)}
  {card(40, "Cold launch", [("Median first appearance", f"{launch_median:.1f} ms", YELLOW), ("P95 first appearance", f"{launch_p95:.1f} ms", YELLOW), ("Installed Release", "verified", PRIMARY)])}
  {card(340, "Popover closed", state_metrics(closed))}
  {card(640, "Popover open", state_metrics(opened))}
</svg>
'''
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(svg, encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"performance chart failed: {error}")
