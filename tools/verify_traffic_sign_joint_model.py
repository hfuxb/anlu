"""独立复算照片格网的强弱模板和头部、竖杆证据；不代表完整RTL或实板。"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = (0x6666, 0x4472, 0x22E4)
USABLE = 0x6FF6


def legacy_class(mask):
    hits = [(mask & USABLE & template).bit_count() for template in TEMPLATES]
    extra = [(mask & USABLE & ~template).bit_count() for template in TEMPLATES]
    if hits[1] >= 5 and extra[1] <= 1 and hits[1] >= hits[0] and hits[1] >= hits[2] + 2:
        return "L"
    if hits[2] >= 5 and extra[2] <= 1 and hits[2] >= hits[0] and hits[2] >= hits[1] + 2:
        return "R"
    if hits[0] >= 5 and extra[0] <= 2 and hits[0] >= hits[1] and hits[0] >= hits[2]:
        return "S"
    return "?"


def joint_class(counts, area):
    strong = sum(int(count * 80 >= area) << index for index, count in enumerate(counts))
    weak = sum(int(count * 160 >= area) << index for index, count in enumerate(counts))
    hits = [(weak & USABLE & template).bit_count() for template in TEMPLATES]
    extra = [(strong & USABLE & ~template).bit_count() for template in TEMPLATES]
    head = counts[1] + counts[4] - counts[2] - counts[7]
    stem = counts[10] + counts[14] - counts[9] - counts[13]
    if head * 160 > area and stem * 160 > area and hits[1] >= 5 and extra[1] <= 2 and hits[1] >= hits[2] + 1:
        return "L"
    if head * 160 < -area and stem * 160 < -area and hits[2] >= 5 and extra[2] <= 2 and hits[2] >= hits[1] + 1:
        return "R"
    return legacy_class(strong)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    report = {"boundary": "固定96像素取样框，牌面水平和垂直偏移各±4像素；未模拟候选扫描", "samples": {}}
    for name, truth in [("left", "L"), ("right", "R"), ("straight", "S")]:
        path = ROOT / f"sim/video720/fixtures/sign_{name}_96.mem"
        values = [int(line, 16) for line in path.read_text(encoding="utf-8").splitlines()
                  if line and not line.startswith("//")]
        pixels = np.array(values, dtype=np.int32).reshape(96, 96)
        red, green, blue = (pixels >> 16) & 255, (pixels >> 8) & 255, pixels & 255
        white = (red >= 150) & (green >= 150) & (blue >= 150) & (abs(red-green) < 40) & (abs(red-blue) < 40)
        padded = np.pad(white, 16)
        rows = []
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                roi = padded[16-dy:112-dy, 16-dx:112-dx]
                counts = [int(roi[y*24:(y+1)*24, x*24:(x+1)*24].sum()) for y in range(4) for x in range(4)]
                mask = sum(int(count*80 >= 9216) << index for index, count in enumerate(counts))
                rows.append({"dx": dx, "dy": dy, "baseline": legacy_class(mask), "joint": joint_class(counts, 9216)})
        summary = {"fixture_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                   "baseline_correct": sum(row["baseline"] == truth for row in rows),
                   "joint_correct": sum(row["joint"] == truth for row in rows),
                   "joint_wrong": sum(row["joint"] not in [truth, "?"] for row in rows),
                   "poses": rows}
        assert summary["joint_correct"] == (80 if truth == "S" else 81)
        assert summary["joint_wrong"] == 0
        report["samples"][name] = summary
        print(name, summary["baseline_correct"], "->", summary["joint_correct"], "/81")
    Path(args.out).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
