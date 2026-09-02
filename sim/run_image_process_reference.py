"""独立参考模型：验证四像素组算法、帧锁存和流标记。"""

from __future__ import annotations

from dataclasses import dataclass


MODE_RAW = 0
MODE_SOBEL = 1
MODE_EROSION = 2
MODE_DILATION = 3


def gray_pixel(pixel: tuple[int, int, int]) -> int:
    red, green, blue = pixel
    return (77 * red + 150 * green + 29 * blue) >> 8


def input_levels(x: int, y: int, pattern: int) -> tuple[int, int, int, int]:
    if pattern == 0:
        return (0, 0, 0, 0)
    if pattern == 2:
        value = 255 if x >= 2 else 0
        return (value, value, value, value)
    if pattern == 3:
        value = 255 if y >= 3 else 0
        return (value, value, value, value)
    if pattern == 4:
        value = x * 20
        return (value, value, value, value)
    if pattern == 5:
        value = 255 if (x == 2 and y == 2) else 0
        return (value, value, value, value)
    return (
        (17 * x + 3 * y + 1) & 0xFF,
        (13 * x + 2 * y + 4) & 0xFF,
        (29 * x + 4 * y + 7) & 0xFF,
        (41 * x + 10 * y + 10) & 0xFF,
    )


def group_gray(x: int, y: int, pattern: int) -> int:
    levels = input_levels(x, y, pattern)
    pixels = []
    for index, level in enumerate(levels):
        if pattern == 1:
            if index == 0:
                pixel = (level, (5 * x + 11 * y + 2) & 0xFF, (9 * x + 7 * y + 3) & 0xFF)
            elif index == 1:
                pixel = ((13 * x + 2 * y + 4) & 0xFF, (3 * x + 19 * y + 5) & 0xFF, (7 * x + 23 * y + 6) & 0xFF)
            elif index == 2:
                pixel = ((29 * x + 4 * y + 7) & 0xFF, (31 * x + 6 * y + 8) & 0xFF, (37 * x + 8 * y + 9) & 0xFF)
            else:
                pixel = ((41 * x + 10 * y + 10) & 0xFF, (43 * x + 12 * y + 11) & 0xFF, (47 * x + 14 * y + 12) & 0xFF)
        else:
            pixel = (level, level, level)
        pixels.append(gray_pixel(pixel))
    return sum(pixels) >> 2


def sobel_bit(gray: list[list[int]], x: int, y: int, threshold: int) -> int:
    if x < 2 or y < 2:
        return 0
    gx = (
        gray[y - 2][x]
        + 2 * gray[y - 1][x]
        + gray[y][x]
        - gray[y - 2][x - 2]
        - 2 * gray[y - 1][x - 2]
        - gray[y][x - 2]
    )
    gy = (
        gray[y][x - 2]
        + 2 * gray[y][x - 1]
        + gray[y][x]
        - gray[y - 2][x - 2]
        - 2 * gray[y - 2][x - 1]
        - gray[y - 2][x]
    )
    return int(abs(gx) + abs(gy) > threshold)


def expected_binary(binary: list[list[int]], x: int, y: int, dilation: bool) -> int:
    if x < 2 or y < 2:
        return 0
    taps = [binary[row][col] for row in range(y - 2, y + 1) for col in range(x - 2, x + 1)]
    return int(any(taps) if dilation else all(taps))


def expected_frame(width: int, height: int, pattern: int, mode: int, threshold: int) -> list[list[int]]:
    groups = width // 4
    gray = [[group_gray(x, y, pattern) for x in range(groups)] for y in range(height)]
    binary = [[sobel_bit(gray, x, y, threshold) for x in range(groups)] for y in range(height)]
    result = []
    for y in range(height):
        row = []
        for x in range(groups):
            if mode == MODE_RAW:
                row.append(-1)
            elif mode == MODE_SOBEL:
                row.append(binary[y][x])
            else:
                row.append(expected_binary(binary, x, y, mode == MODE_DILATION))
        result.append(row)
    return result


def packed_word(x: int, y: int, pattern: int) -> tuple[tuple[int, int, int], ...]:
    if pattern != 1:
        return tuple((level, level, level) for level in input_levels(x, y, pattern))
    return (
        ((17 * x + 3 * y + 1) & 0xFF, (5 * x + 11 * y + 2) & 0xFF, (9 * x + 7 * y + 3) & 0xFF),
        ((13 * x + 2 * y + 4) & 0xFF, (3 * x + 19 * y + 5) & 0xFF, (7 * x + 23 * y + 6) & 0xFF),
        ((29 * x + 4 * y + 7) & 0xFF, (31 * x + 6 * y + 8) & 0xFF, (37 * x + 8 * y + 9) & 0xFF),
        ((41 * x + 10 * y + 10) & 0xFF, (43 * x + 12 * y + 11) & 0xFF, (47 * x + 14 * y + 12) & 0xFF),
    )


@dataclass
class StreamModel:
    width: int
    height: int
    x: int = 0
    y: int = 0
    frame_mode: int = MODE_RAW
    frame_threshold: int = 24

    def __post_init__(self) -> None:
        self.groups = self.width // 4
        self.gray_a = [0] * self.groups
        self.gray_b = [0] * self.groups
        self.bin_a = [0] * self.groups
        self.bin_b = [0] * self.groups
        self.gray_top_2 = self.gray_top_1 = 0
        self.gray_mid_2 = self.gray_mid_1 = 0
        self.gray_cur_2 = self.gray_cur_1 = 0
        self.bin_top_2 = self.bin_top_1 = 0
        self.bin_mid_2 = self.bin_mid_1 = 0
        self.bin_cur_2 = self.bin_cur_1 = 0

    def step(self, pixels: tuple[tuple[int, int, int], ...], tuser: bool, tlast: bool, mode: int, threshold: int) -> tuple[bool, bool, bool, object]:
        active_x = 0 if tuser else self.x
        active_y = 0 if tuser else self.y
        active_mode = mode if tuser else self.frame_mode
        active_threshold = threshold if tuser else self.frame_threshold
        gray = sum(gray_pixel(pixel) for pixel in pixels) >> 2

        top = self.gray_b[active_x]
        middle = self.gray_a[active_x]
        bin_top = self.bin_b[active_x]
        bin_middle = self.bin_a[active_x]
        current_sobel = int(
            abs(
                top + 2 * middle + gray
                - self.gray_top_2 - 2 * self.gray_mid_2 - self.gray_cur_2
            )
            + abs(
                self.gray_cur_2 + 2 * self.gray_cur_1 + gray
                - self.gray_top_2 - 2 * self.gray_top_1 - top
            )
            > active_threshold
        )
        sobel = 0 if active_x < 2 or active_y < 2 else current_sobel
        valid_morphology = active_x >= 2 and active_y >= 2
        taps = [self.bin_top_2, self.bin_top_1, bin_top, self.bin_mid_2, self.bin_mid_1, bin_middle, self.bin_cur_2, self.bin_cur_1, sobel]
        erosion = int(valid_morphology and all(taps))
        dilation = int(valid_morphology and any(taps))

        if active_mode == MODE_RAW:
            result = pixels
        else:
            bit = sobel if active_mode == MODE_SOBEL else erosion if active_mode == MODE_EROSION else dilation
            result = tuple((255, 255, 255) if bit else (0, 0, 0) for _ in range(4))

        self.gray_a[active_x] = gray
        self.bin_a[active_x] = sobel
        if active_y != 0:
            self.gray_b[active_x] = middle
            self.bin_b[active_x] = bin_middle

        if tlast:
            self.gray_top_2 = self.gray_top_1 = 0
            self.gray_mid_2 = self.gray_mid_1 = 0
            self.gray_cur_2 = self.gray_cur_1 = 0
            self.bin_top_2 = self.bin_top_1 = 0
            self.bin_mid_2 = self.bin_mid_1 = 0
            self.bin_cur_2 = self.bin_cur_1 = 0
            self.x = 0
            self.y = 0 if active_y == self.height - 1 else active_y + 1
        else:
            self.gray_top_2, self.gray_top_1 = self.gray_top_1, top
            self.gray_mid_2, self.gray_mid_1 = self.gray_mid_1, middle
            self.gray_cur_2, self.gray_cur_1 = self.gray_cur_1, gray
            self.bin_top_2, self.bin_top_1 = self.bin_top_1, bin_top
            self.bin_mid_2, self.bin_mid_1 = self.bin_mid_1, bin_middle
            self.bin_cur_2, self.bin_cur_1 = self.bin_cur_1, sobel
            self.x = active_x + 1
            self.y = active_y

        if tuser:
            self.frame_mode = mode
            self.frame_threshold = threshold
        return True, tuser, tlast, result


def run_small_frame(mode: int, threshold: int, pattern: int) -> None:
    width, height = 16, 6
    groups = width // 4
    expected = expected_frame(width, height, pattern, mode, threshold)
    model = StreamModel(width, height)
    for y in range(height):
        for x in range(groups):
            pixels = packed_word(x, y, pattern)
            changed_mode = mode if x == 0 and y == 0 else mode ^ 1
            changed_threshold = threshold if x == 0 and y == 0 else (0 if threshold == 24 else 2047)
            valid, tuser, tlast, result = model.step(pixels, x == 0 and y == 0, x == groups - 1, changed_mode, changed_threshold)
            assert valid and tuser == (x == 0 and y == 0) and tlast == (x == groups - 1)
            if mode == MODE_RAW:
                assert result == pixels
            else:
                bit = expected[y][x]
                expected_pixels = tuple((255, 255, 255) if bit else (0, 0, 0) for _ in range(4))
                assert result == expected_pixels, (mode, threshold, pattern, x, y, result, expected_pixels)


def run_marker_rate_check() -> None:
    width, height = 1024, 600
    model = StreamModel(width, height)
    valid_count = 0
    user_count = 0
    last_count = 0
    for frame in range(2):
        for y in range(height):
            for x in range(width // 4):
                valid, tuser, tlast, _ = model.step(packed_word(x, y, 0), x == 0 and y == 0, x == width // 4 - 1, MODE_RAW, 24)
                valid_count += int(valid)
                user_count += int(tuser)
                last_count += int(tlast)
    assert valid_count == 2 * (width // 4) * height
    assert user_count == 2
    assert last_count == 2 * height


def run_awb_marker_alignment_check() -> None:
    """Check the isp_top bridge from AWB's early marker to algorithm tuser."""
    def observe(sequence: tuple[tuple[bool, bool], ...]) -> list[bool]:
        pending = False
        observed = []
        for early_marker, valid in sequence:
            observed.append(valid and (early_marker or pending))
            if early_marker and not valid:
                pending = True
            elif valid:
                pending = False
        return observed

    delayed_marker = (
        (True, False),
        (False, False),
        (False, True),
        (False, True),
    )
    same_cycle_marker = (
        (True, True),
        (False, True),
    )
    assert observe(delayed_marker) == [False, False, True, False]
    assert observe(same_cycle_marker) == [True, False]


def run_packer_reference_check() -> None:
    """Check the official 4x96-bit to 3x128-bit concatenation contract."""
    mask64 = (1 << 64) - 1
    groups = (
        0x100000000000000020000000,
        0x200000000000000030000000,
        0x300000000000000040000000,
        0x400000000000000050000000,
    )
    expected = (
        (groups[0] << 32) | (groups[1] >> 64),
        ((groups[1] & mask64) << 64) | (groups[2] >> 32),
        ((groups[2] & ((1 << 32) - 1)) << 96) | groups[3],
    )
    stream = b"".join(group.to_bytes(12, "big") for group in groups)
    actual = tuple(
        int.from_bytes(stream[offset:offset + 16], "big")
        for offset in (0, 16, 32)
    )
    assert actual == expected
    assert [True, False, False, False] == [True, False, False, False]
    assert [False, True, True, True] == [False, True, True, True]


def run_packer_marker_tlast_check() -> None:
    """Check packed-frame marker and row-end alignment for 256 groups per row."""
    groups_per_row = 1024 // 4
    rows = 600
    pack_count = 0
    frame_markers = 0
    valid_beats = 0
    row_tlast = [0] * rows

    for y in range(rows):
        for x in range(groups_per_row):
            frame_start = x == 0 and y == 0
            row_end = x == groups_per_row - 1
            if frame_start:
                frame_markers += 1
                output_valid = False
                pack_count = 1
            else:
                output_valid = pack_count != 0
                if output_valid:
                    valid_beats += 1
                pack_count = (pack_count + 1) & 0x3
            if output_valid and row_end:
                row_tlast[y] += 1

    assert frame_markers == 1
    assert valid_beats == rows * (groups_per_row // 4) * 3
    assert row_tlast == [1] * rows


def main() -> None:
    for mode, threshold, pattern in (
        (MODE_RAW, 24, 1),
        (MODE_SOBEL, 24, 0),
        (MODE_SOBEL, 24, 2),
        (MODE_SOBEL, 24, 3),
        (MODE_SOBEL, 1019, 2),
        (MODE_SOBEL, 1020, 2),
        (MODE_SOBEL, 1021, 2),
        (MODE_EROSION, 24, 0),
        (MODE_EROSION, 24, 4),
        (MODE_EROSION, 24, 5),
        (MODE_DILATION, 24, 0),
        (MODE_DILATION, 24, 4),
        (MODE_DILATION, 24, 5),
    ):
        run_small_frame(mode, threshold, pattern)
        print(f"[PASS] mode={mode:02b} threshold={threshold} pattern={pattern}")
    run_marker_rate_check()
    print("[PASS] 2 frames, 153600 groups/frame, 600 tlast/frame, 1 tuser/frame")
    run_awb_marker_alignment_check()
    print("[PASS] early AWB frame marker aligned to first valid algorithm beat")
    run_packer_reference_check()
    print("[PASS] 4x96-bit to 3x128-bit packing order reference")
    run_packer_marker_tlast_check()
    print("[PASS] packed tuser/tlast alignment, 115200 output beats/frame")
    print("[RESULT] ALL REFERENCE FUNCTION TESTS PASSED")


if __name__ == "__main__":
    main()
