#!/usr/bin/env python3
"""Render the 10-second BLOMIX 2.5D promotional film.

The renderer deliberately uses simple flat-shaded geometry so the result stays
close to the game's visual language. Frames are streamed directly to ffmpeg;
no intermediate image sequence is written to disk.
"""

from __future__ import annotations

import argparse
import math
import random
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError as exc:
    raise SystemExit(
        "Pillow is required. Run:\n"
        "python3 -m pip install --target /tmp/blomix-video-python pillow\n"
        "PYTHONPATH=/tmp/blomix-video-python python3 scripts/render-promo-2_5d.py"
    ) from exc


ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = ROOT / "Blomix/Blomix/ChangaOne-Regular.ttf"
SOUND_DIR = ROOT / "Blomix/Blomix/Sounds"

DURATION = 10.0
BACKGROUND = "#F8F5EE"
SCENE_BACKGROUND = "#F5EEDF"
EMPTY_CELL = "#EBE3D0"
GRID_LINE = "#D8D4CB"
TEXT = "#262626"
PALETTE = {
    "blue": "#299D8F",
    "red": "#E66F51",
    "purple": "#264753",
    "yellow": "#E8C46A",
    "green": "#8BB17D",
    "orange": "#F4A261",
}


Vec3 = tuple[float, float, float]
Vec2 = tuple[float, float]
Color = tuple[int, int, int]


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def mix(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def smoothstep(t: float) -> float:
    t = clamp(t)
    return t * t * (3.0 - 2.0 * t)


def ease_out(t: float) -> float:
    return 1.0 - (1.0 - clamp(t)) ** 3


def window(t: float, start: float, end: float) -> float:
    return clamp((t - start) / max(end - start, 1e-9))


def rgb(value: str | Color) -> Color:
    if isinstance(value, tuple):
        return value
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def blend_color(a: str | Color, b: str | Color, t: float) -> Color:
    ca, cb = rgb(a), rgb(b)
    t = clamp(t)
    return tuple(round(mix(ca[i], cb[i], t)) for i in range(3))  # type: ignore[return-value]


def shade(value: str | Color, factor: float) -> Color:
    c = rgb(value)
    return tuple(round(clamp(channel * factor, 0, 255)) for channel in c)  # type: ignore[return-value]


def add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(v: Vec3, scalar: float) -> Vec3:
    return (v[0] * scalar, v[1] * scalar, v[2] * scalar)


def dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def norm(v: Vec3) -> Vec3:
    length = math.sqrt(max(dot(v, v), 1e-12))
    return mul(v, 1.0 / length)


def lerp3(a: Vec3, b: Vec3, t: float) -> Vec3:
    return (mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t))


@dataclass(frozen=True)
class Camera:
    position: Vec3
    target: Vec3
    fov: float
    width: int
    height: int

    @property
    def basis(self) -> tuple[Vec3, Vec3, Vec3]:
        forward = norm(sub(self.target, self.position))
        right = norm(cross(forward, (0.0, 0.0, 1.0)))
        up = norm(cross(right, forward))
        return right, up, forward

    def camera_point(self, point: Vec3) -> Vec3:
        right, up, forward = self.basis
        relative = sub(point, self.position)
        return (dot(relative, right), dot(relative, up), dot(relative, forward))

    def project(self, point: Vec3) -> Vec2 | None:
        x, y, z = self.camera_point(point)
        if z <= 0.08:
            return None
        focal = 0.5 * self.height / math.tan(math.radians(self.fov) * 0.5)
        return (self.width * 0.5 + focal * x / z, self.height * 0.5 - focal * y / z)


@dataclass(frozen=True)
class Block:
    col: int
    row: int
    color: str

    @property
    def center(self) -> Vec3:
        return (self.col - 3.5, 3.5 - self.row, 0.0)


@dataclass(frozen=True)
class Launch:
    color: str
    col: int
    row: int
    start: float
    end: float
    clear_start: float | None = None
    clear_cells: tuple[tuple[int, int], ...] = ()

    @property
    def target(self) -> Vec3:
        return (self.col - 3.5, 3.5 - self.row, 0.0)

    @property
    def clear_end(self) -> float:
        if self.clear_start is None:
            return math.inf
        return self.clear_start + max(len(self.clear_cells) - 1, 0) * 0.04 + 0.50


# Every occupied column is contiguous from row 0: this is a legal BLOMIX board.
INITIAL_BOARD: tuple[Block, ...] = (
    Block(0, 0, "orange"), Block(1, 0, "blue"), Block(2, 0, "purple"),
    Block(3, 0, "red"), Block(4, 0, "yellow"), Block(5, 0, "green"),
    Block(6, 0, "blue"), Block(7, 0, "red"),
    Block(0, 1, "purple"), Block(1, 1, "green"), Block(2, 1, "red"),
    Block(3, 1, "yellow"), Block(4, 1, "blue"), Block(5, 1, "purple"),
    Block(6, 1, "red"), Block(7, 1, "green"),
    Block(0, 2, "blue"), Block(1, 2, "yellow"), Block(2, 2, "purple"),
    # Four connected orange blox wait legally at the top of columns 3–6.
    Block(3, 2, "orange"), Block(4, 2, "orange"), Block(5, 2, "orange"),
    Block(6, 2, "orange"), Block(7, 2, "blue"),
    Block(0, 3, "green"),
    # Four red blox; the first launch completes and clears this whole component.
    Block(1, 3, "red"), Block(2, 3, "red"), Block(3, 3, "red"),
    Block(4, 3, "red"),
)

LAUNCHES: tuple[Launch, ...] = (
    Launch(
        "red", 3, 4, 1.35, 1.75, 1.90,
        ((1, 3), (2, 3), (3, 3), (4, 3), (3, 4)),
    ),
    Launch("blue", 6, 3, 2.75, 3.10),
    Launch("yellow", 0, 4, 3.75, 4.10),
    Launch(
        "orange", 5, 3, 5.05, 5.55, 5.70,
        ((3, 2), (4, 2), (5, 2), (6, 2), (5, 3)),
    ),
)


def launch_position(launch: Launch, t: float) -> Vec3:
    p = ease_out(window(t, launch.start, launch.end))
    start = (launch.target[0], -5.35, 0.0)
    position = lerp3(start, launch.target, p)
    return (position[0], position[1], 0.10 + math.sin(p * math.pi) * 0.26)


def active_blocks(t: float) -> list[Block]:
    blocks = list(INITIAL_BOARD)
    for launch in LAUNCHES:
        if t >= launch.end:
            blocks.append(Block(launch.col, launch.row, launch.color))
        if launch.clear_start is not None and t >= launch.clear_end:
            removed = set(launch.clear_cells)
            blocks = [block for block in blocks if (block.col, block.row) not in removed]
            # BLOMIX compacts every affected column toward row 0 after a clear.
            compacted: list[Block] = []
            for col in range(8):
                column = sorted((block for block in blocks if block.col == col), key=lambda block: block.row)
                compacted.extend(
                    Block(col, target_row, block.color)
                    for target_row, block in enumerate(column)
                )
            blocks = compacted
    return blocks


def block_center_at(block: Block, t: float) -> Vec3:
    """Animate the visible post-clear compaction with the game's 0.25 s easeOut."""
    final_clear = LAUNCHES[-1]
    compaction_start = final_clear.clear_end
    # The blue blox in column 6 is below the cleared orange blox: row 3 → row 2.
    if (
        block.col == 6 and block.row == 2 and block.color == "blue"
        and compaction_start <= t < compaction_start + 0.25
    ):
        p = ease_out((t - compaction_start) / 0.25)
        old_center = Block(6, 3, "blue").center
        return lerp3(old_center, block.center, p)
    return block.center


def camera_at(t: float, width: int, height: int) -> Camera:
    if t < 4.15:
        p = smoothstep(window(t, 1.15, 4.15))
        position = lerp3((0.0, -27.0, 11.5), (-2.4, -10.5, 7.0), p)
        target = lerp3((0.0, 7.0, 0.0), (0.0, 0.6, 0.15), p)
        return Camera(position, target, mix(48.0, 53.0, p), width, height)
    if t < 7.15:
        p = smoothstep(window(t, 4.15, 5.45))
        drift = smoothstep(window(t, 5.45, 7.15))
        base_position = lerp3((-2.4, -10.5, 7.0), (-2.35, -6.25, 1.85), p)
        position = add(base_position, (0.34 * drift, 0.22 * drift, 0.08 * drift))
        final_launch = LAUNCHES[-1]
        # Keep the point of interest fixed on the future orange chain. Tracking
        # the incoming blox used to jump the look-at target back to its launch
        # point for one frame when the flight began.
        close_target = (final_launch.target[0], final_launch.target[1] + 0.7, 0.35)
        base_target = lerp3((0.0, 0.6, 0.15), close_target, p)
        target = add(base_target, (0.14 * drift, 0.06 * drift, 0.0))
        return Camera(position, target, mix(53.0, 46.0, p), width, height)
    p = smoothstep(window(t, 7.15, 8.55))
    # Start exactly at the drifted endpoint of the previous camera segment.
    position = lerp3((-2.01, -6.03, 1.93), (0.0, -15.0, 13.0), p)
    target = lerp3((1.64, 1.26, 0.35), (0.0, 0.0, 0.0), p)
    return Camera(position, target, mix(46.0, 47.0, p), width, height)


def draw_world_line(
    draw: ImageDraw.ImageDraw,
    camera: Camera,
    a: Vec3,
    b: Vec3,
    fill: Color,
    width: int,
) -> None:
    ca, cb = camera.camera_point(a), camera.camera_point(b)
    near = 0.09
    if ca[2] <= near and cb[2] <= near:
        return
    if ca[2] <= near or cb[2] <= near:
        behind, front = (ca, cb) if ca[2] <= near else (cb, ca)
        amount = (near - behind[2]) / (front[2] - behind[2])
        clipped = (
            mix(behind[0], front[0], amount),
            mix(behind[1], front[1], amount),
            near,
        )
        if ca[2] <= near:
            ca = clipped
        else:
            cb = clipped
    focal = 0.5 * camera.height / math.tan(math.radians(camera.fov) * 0.5)
    pa = (camera.width * 0.5 + focal * ca[0] / ca[2], camera.height * 0.5 - focal * ca[1] / ca[2])
    pb = (camera.width * 0.5 + focal * cb[0] / cb[2], camera.height * 0.5 - focal * cb[1] / cb[2])
    draw.line((pa, pb), fill=fill, width=width)


def polygon(camera: Camera, points: Sequence[Vec3]) -> list[Vec2] | None:
    projected = [camera.project(point) for point in points]
    if any(point is None for point in projected):
        return None
    return [point for point in projected if point is not None]


def draw_plane_grid(draw: ImageDraw.ImageDraw, camera: Camera, scale: float) -> None:
    line_color = rgb(GRID_LINE)
    thin = max(1, round(scale))
    for index in range(-32, 33):
        major = index % 8 == 0
        color = blend_color(BACKGROUND, line_color, 0.60 if major else 0.35)
        draw_world_line(draw, camera, (index, -32.0, 0.0), (index, 32.0, 0.0), color, thin)
        draw_world_line(draw, camera, (-32.0, index, 0.0), (32.0, index, 0.0), color, thin)


def draw_board_cells(draw: ImageDraw.ImageDraw, camera: Camera, scale: float) -> None:
    for row in range(8):
        for col in range(8):
            x, y = col - 3.5, 3.5 - row
            half = 0.46
            points = polygon(camera, (
                (x - half, y - half, 0.012), (x + half, y - half, 0.012),
                (x + half, y + half, 0.012), (x - half, y + half, 0.012),
            ))
            if points:
                draw.polygon(points, fill=rgb(EMPTY_CELL))
                draw.line(points + [points[0]], fill=rgb("#D5CDBD"), width=max(1, round(scale)))
    outline = ((-4.08, -4.08, 0.018), (4.08, -4.08, 0.018),
               (4.08, 4.08, 0.018), (-4.08, 4.08, 0.018))
    points = polygon(camera, outline)
    if points:
        draw.line(points + [points[0]], fill=rgb("#C8C0B0"), width=max(2, round(1.5 * scale)))


def cuboid_faces(center: Vec3, size: float, height: float) -> tuple[tuple[Vec3, ...], ...]:
    x, y, z = center
    half = size * 0.5
    bottom = (
        (x - half, y - half, z), (x + half, y - half, z),
        (x + half, y + half, z), (x - half, y + half, z),
    )
    top = tuple((px, py, z + height) for px, py, _ in bottom)
    return (
        (bottom[0], bottom[1], top[1], top[0]),
        (bottom[1], bottom[2], top[2], top[1]),
        (bottom[2], bottom[3], top[3], top[2]),
        (bottom[3], bottom[0], top[0], top[3]),
        top,
    )


def draw_cuboids(
    draw: ImageDraw.ImageDraw,
    camera: Camera,
    cuboids: Iterable[tuple[Vec3, float, float, Color]],
) -> None:
    faces: list[tuple[float, list[Vec2], Color]] = []
    factors = (0.72, 0.80, 0.64, 0.70, 1.0)
    for center, size, height, color in cuboids:
        for index, face in enumerate(cuboid_faces(center, size, height)):
            points = polygon(camera, face)
            if not points:
                continue
            depth = sum(camera.camera_point(point)[2] for point in face) / len(face)
            faces.append((depth, points, shade(color, factors[index])))
    for _, points, color in sorted(faces, key=lambda item: item[0], reverse=True):
        draw.polygon(points, fill=color)


def clear_state(
    t: float,
    launch: Launch,
    col: int,
    row: int,
) -> tuple[float, Color] | None:
    if launch.clear_start is None or (col, row) not in launch.clear_cells:
        return (1.0, rgb(PALETTE[launch.color]))
    order = launch.clear_cells.index((col, row))
    start = launch.clear_start + order * 0.04
    local = t - start
    if local < 0:
        return (1.0, rgb(PALETTE[launch.color]))
    if local < 0.20:
        return (mix(1.0, 1.30, ease_out(local / 0.20)), rgb(PALETTE[launch.color]))
    if local < 0.36:
        p = smoothstep((local - 0.20) / 0.16)
        return (mix(1.30, 1.0, p), blend_color(PALETTE[launch.color], "#FFFFFF", 0.30 * p))
    if local < 0.50:
        p = (local - 0.36) / 0.14
        return (mix(1.0, 0.82, p), blend_color(PALETTE[launch.color], EMPTY_CELL, p))
    return None


def draw_blocks(draw: ImageDraw.ImageDraw, camera: Camera, t: float) -> None:
    items: list[tuple[Vec3, float, float, Color]] = []
    for block in active_blocks(t):
        clearing = next(
            (
                launch for launch in LAUNCHES
                if launch.clear_start is not None
                and launch.clear_start <= t < launch.clear_end
                and (block.col, block.row) in launch.clear_cells
            ),
            None,
        )
        state = (
            clear_state(t, clearing, block.col, block.row)
            if clearing is not None
            else (1.0, rgb(PALETTE[block.color]))
        )
        if state is None:
            continue
        size_scale, color = state
        size = 0.88 * size_scale
        height = 0.46 * size_scale
        placed_by = next(
            (
                launch for launch in LAUNCHES
                if launch.col == block.col and launch.row == block.row
                and launch.end <= t < launch.end + 0.15
            ),
            None,
        )
        if placed_by is not None:
            landing = t - placed_by.end
            if landing < 0.09:
                p = ease_out(landing / 0.09)
                size *= mix(1.0, 1.20, p)
                height *= mix(1.0, 0.78, p)
            elif landing < 0.12:
                p = ease_out((landing - 0.09) / 0.03)
                size *= mix(1.20, 0.94, p)
                height *= mix(0.78, 1.15, p)
            else:
                p = smoothstep((landing - 0.12) / 0.03)
                size *= mix(0.94, 1.0, p)
                height *= mix(1.15, 1.0, p)
        items.append((block_center_at(block, t), size, height, color))

    for launch in LAUNCHES:
        if launch.start <= t < launch.end:
            flight = 1.0 - smoothstep(window(t, launch.start, launch.end))
            items.append((
                launch_position(launch, t),
                0.88 * mix(1.0, 0.82, flight),
                0.46 * mix(1.0, 1.25, flight),
                rgb(PALETTE[launch.color]),
            ))

    draw_cuboids(draw, camera, items)


def screen_radius(camera: Camera, position: Vec3, world_radius: float) -> float:
    center = camera.project(position)
    edge = camera.project((position[0] + world_radius, position[1], position[2]))
    if center is None or edge is None:
        return 0.0
    return max(1.0, math.dist(center, edge))


def draw_dot(
    draw: ImageDraw.ImageDraw,
    camera: Camera,
    position: Vec3,
    world_radius: float,
    color: Color,
    alpha: int,
) -> None:
    point = camera.project(position)
    if point is None:
        return
    radius = screen_radius(camera, position, world_radius)
    draw.ellipse(
        (point[0] - radius, point[1] - radius, point[0] + radius, point[1] + radius),
        fill=color + (max(0, min(255, alpha)),),
    )


def draw_flight_trail(image: Image.Image, camera: Camera, t: float) -> None:
    """Recreate makeTrailSpawnAction: 25 spawns/s, 3 lanes + 4 micro dots."""
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for launch_index, launch in enumerate(LAUNCHES):
        spawn_count = math.ceil((launch.end - launch.start) / 0.04)
        for index in range(spawn_count + 1):
            spawned = launch.start + index * 0.04
            age = t - spawned
            if age < 0.0 or age >= 0.38 or spawned > launch.end:
                continue
            fade = 1.0 - age / 0.38
            origin = launch_position(launch, spawned)
            rng = random.Random(5100 + launch_index * 100 + index)
            for lane, x_offset in enumerate((0.0, -0.225, 0.225)):
                radius = rng.uniform(0.045, 0.075) if lane == 0 else rng.uniform(0.025, 0.05)
                y_range = (-0.125, 0.05) if lane == 0 else (-0.30, 0.05)
                position = (
                    origin[0] + x_offset + rng.uniform(-0.10, 0.10),
                    origin[1] + rng.uniform(*y_range),
                    origin[2] + 0.22,
                )
                draw_dot(
                    draw, camera, position, radius, rgb(PALETTE[launch.color]),
                    round(230 * fade),
                )
            for _ in range(4):
                position = (
                    origin[0] + rng.uniform(-0.375, 0.375),
                    origin[1] + rng.uniform(-0.50, 0.0),
                    origin[2] + rng.uniform(0.12, 0.30),
                )
                draw_dot(
                    draw, camera, position, 0.025, rgb(PALETTE[launch.color]),
                    round(230 * fade),
                )
    image.alpha_composite(layer)


def draw_landing_particles(image: Image.Image, camera: Camera, t: float) -> None:
    """Two-layer impact sparkle matching spawnLandingImpactSparkles."""
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for launch_index, launch in enumerate(LAUNCHES):
        age = t - launch.end
        if age < 0.0 or age >= 0.80:
            continue
        color = rgb(PALETTE[launch.color])
        rng = random.Random(8851 + launch_index)
        for _ in range(12):
            angle = rng.uniform(0.0, math.tau)
            start = rng.uniform(0.425, 0.575)
            end = start + rng.uniform(0.30, 0.65)
            radius = rng.uniform(0.02, 0.045)
            if age >= 0.22:
                continue
            p = ease_out(age / 0.22)
            distance = mix(start, end, p)
            alpha = round(230 * min(age / 0.03, 1.0) * (1.0 - p))
            position = (
                launch.target[0] + math.cos(angle) * distance,
                launch.target[1] + math.sin(angle) * distance,
                0.34 + math.sin(math.pi * p) * 0.15,
            )
            draw_dot(draw, camera, position, radius, color, alpha)
        for _ in range(38):
            angle = rng.uniform(0.0, math.tau)
            start = rng.uniform(0.375, 0.625)
            drift = rng.uniform(0.025, 0.125)
            radius = rng.uniform(0.0125, 0.03)
            peak = rng.uniform(0.60, 0.95)
            p = ease_out(age / 0.80)
            alpha = round(255 * peak * min(age / 0.05, 1.0) * (1.0 - p))
            distance = mix(start, start + drift, p)
            position = (
                launch.target[0] + math.cos(angle) * distance,
                launch.target[1] + math.sin(angle) * distance,
                0.30 + p * rng.uniform(0.0, 0.075),
            )
            draw_dot(draw, camera, position, radius, color, alpha)
    image.alpha_composite(layer)


def draw_particles(
    image: Image.Image,
    camera: Camera,
    t: float,
) -> None:
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for launch_index, launch in enumerate(LAUNCHES):
        if launch.clear_start is None:
            continue
        for cell_index, (col, row) in enumerate(launch.clear_cells):
            rng = random.Random(7400 + launch_index * 100 + cell_index)
            main_count = rng.randint(7, 10)
            start = launch.clear_start + cell_index * 0.04 + 0.20
            p = window(t, start, start + 0.45)
            for particle_index in range(main_count + 10):
                radius = rng.uniform(0.05, 0.0875) if particle_index < main_count else 0.0375
                ox, oy = rng.uniform(-0.36, 0.36), rng.uniform(-0.36, 0.36)
                drift, fall = rng.uniform(-0.12, 0.12), rng.uniform(0.25, 0.55)
                if p <= 0.0 or p >= 1.0:
                    continue
                x, y, _ = Block(col, row, launch.color).center
                position = (
                    x + ox + drift * p,
                    y + oy - fall * p * p,
                    0.38 + 0.12 * math.sin(math.pi * p),
                )
                draw_dot(
                    draw, camera, position, radius * (1.0 - p * 0.20),
                    rgb(PALETTE[launch.color]), round(255 * (1.0 - p)),
                )
    image.alpha_composite(layer)


def title_opacity(t: float, intro: bool) -> float:
    if intro:
        return smoothstep(window(t, 0.05, 0.35)) * (1.0 - smoothstep(window(t, 1.05, 1.45)))
    return smoothstep(window(t, 8.20, 8.65))


def centered_text(
    draw: ImageDraw.ImageDraw,
    text: str,
    y: float,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int, int],
    width: int,
) -> None:
    bounds = draw.textbbox((0, 0), text, font=font)
    text_width = bounds[2] - bounds[0]
    draw.text(((width - text_width) * 0.5, y), text, font=font, fill=fill)


def draw_titles(image: Image.Image, t: float, title_font: ImageFont.FreeTypeFont,
                subtitle_font: ImageFont.FreeTypeFont) -> None:
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    intro = t < 2.0
    opacity = title_opacity(t, intro)
    if opacity <= 0:
        return
    title_y = image.height * (0.39 if intro else 0.375)
    title_fill = rgb(TEXT) + (round(255 * opacity),)
    centered_text(draw, "BLOMIX", title_y, title_font, title_fill, image.width)
    if not intro:
        subtitle_opacity = opacity * smoothstep(window(t, 8.48, 8.82))
        subtitle_fill = rgb(TEXT) + (round(235 * subtitle_opacity),)
        centered_text(
            draw,
            "DES CHAÎNES. DE LA PRESSION. ZÉRO PUB.",
            image.height * 0.645,
            subtitle_font,
            subtitle_fill,
            image.width,
        )
    image.alpha_composite(layer)


def render_frame(t: float, width: int, height: int,
                 title_font: ImageFont.FreeTypeFont,
                 subtitle_font: ImageFont.FreeTypeFont) -> Image.Image:
    scale = height / 1080.0
    image = Image.new("RGBA", (width, height), rgb(BACKGROUND) + (255,))
    camera = camera_at(t, width, height)

    scene_alpha = smoothstep(window(t, 1.12, 1.55))
    end_white = smoothstep(window(t, 7.95, 8.55))
    if scene_alpha > 0.0 and end_white < 1.0:
        scene = Image.new("RGBA", (width, height), rgb(SCENE_BACKGROUND) + (255,))
        draw = ImageDraw.Draw(scene)
        draw_plane_grid(draw, camera, scale)
        draw_board_cells(draw, camera, scale)
        draw_flight_trail(scene, camera, t)
        draw_blocks(draw, camera, t)
        draw_landing_particles(scene, camera, t)
        draw_particles(scene, camera, t)
        effective = scene_alpha * (1.0 - end_white)
        image = Image.blend(image, scene, effective)

    draw_titles(image, t, title_font, subtitle_font)
    return image.convert("RGB")


def run_render(output: Path, width: int, height: int, fps: int) -> None:
    if not FONT_PATH.exists():
        raise SystemExit(f"Missing font: {FONT_PATH}")
    output.parent.mkdir(parents=True, exist_ok=True)
    silent = output.with_name(f"{output.stem}.silent.mp4")
    title_font = ImageFont.truetype(str(FONT_PATH), round(height * 0.24))
    subtitle_font = ImageFont.truetype(str(FONT_PATH), round(height * 0.035))

    encoder = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{width}x{height}",
        "-r", str(fps), "-i", "-", "-an",
        "-c:v", "libx264", "-preset", "medium", "-crf", "17",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(silent),
    ]
    process = subprocess.Popen(encoder, stdin=subprocess.PIPE)
    frame_count = round(DURATION * fps)
    assert process.stdin is not None
    try:
        for frame_index in range(frame_count):
            frame = render_frame(frame_index / fps, width, height, title_font, subtitle_font)
            process.stdin.write(frame.tobytes())
            if frame_index % max(fps, 1) == 0:
                print(f"\rRendering {frame_index / fps:4.1f}/{DURATION:.1f}s", end="", flush=True)
    finally:
        process.stdin.close()
    status = process.wait()
    print()
    if status != 0:
        raise SystemExit(f"ffmpeg video encoding failed with status {status}")

    music = SOUND_DIR / "Puzzle Game 2.mp3"
    transition = SOUND_DIR / "transition.wav"
    chain = SOUND_DIR / "chain_new.wav"
    for asset in (music, transition, chain):
        if not asset.exists():
            raise SystemExit(f"Missing audio asset: {asset}")

    audio_filter = (
        "[1:a]atrim=0:10,asetpts=PTS-STARTPTS,volume=0.28,"
        "afade=t=in:st=0:d=0.35,afade=t=out:st=9.25:d=0.75[m];"
        "[2:a]adelay=1120|1120,volume=0.58[transition];"
        "[3:a]adelay=1900|1900,volume=0.76[first_chain];"
        "[4:a]adelay=5700|5700,volume=0.80[last_chain];"
        "[m][transition][first_chain][last_chain]"
        "amix=inputs=4:duration=longest:normalize=0,"
        "alimiter=limit=0.95,atrim=0:10[a]"
    )
    mux = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-i", str(silent), "-i", str(music), "-i", str(transition),
        "-i", str(chain), "-i", str(chain),
        "-filter_complex", audio_filter,
        "-map", "0:v:0", "-map", "[a]", "-c:v", "copy", "-c:a", "aac",
        "-b:a", "256k", "-ar", "48000", "-ac", "2", "-t", "10",
        "-movflags", "+faststart", str(output),
    ]
    subprocess.run(mux, check=True)
    silent.unlink(missing_ok=True)
    print(f"Created {output}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "blomix-promo-2_5d.mp4")
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    parser.add_argument("--fps", type=int, default=60)
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Render a faster 960x540, 30 fps review copy.",
    )
    args = parser.parse_args()
    if args.preview:
        args.width, args.height, args.fps = 960, 540, 30
        if args.output == ROOT / "blomix-promo-2_5d.mp4":
            args.output = ROOT / "blomix-promo-2_5d-preview.mp4"
    return args


if __name__ == "__main__":
    arguments = parse_args()
    run_render(arguments.output, arguments.width, arguments.height, arguments.fps)
