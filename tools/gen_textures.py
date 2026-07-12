#!/usr/bin/env python3
"""Генератор пиксельных текстур для демо "Метроград".

Все текстуры — маленькие PNG с ограниченной палитрой, тайлятся (кроме панелей).
Запуск:  python3 tools/gen_textures.py
Результат кладётся в assets/textures/.
"""
import os
import random
from PIL import Image

random.seed(42)

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
os.makedirs(OUT, exist_ok=True)


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path)
    print("wrote", os.path.relpath(path))


def noisy(base, amount):
    """Случайное подкрашивание пикселя вокруг базового цвета."""
    d = random.randint(-amount, amount)
    return tuple(max(0, min(255, c + d)) for c in base)


def tiled_bricks(size, tile_w, tile_h, color, grout, jitter=10):
    """Кирпичная/плиточная кладка со швами."""
    w = h = size
    img = Image.new("RGB", (w, h), grout)
    px = img.load()
    for by in range(0, h, tile_h):
        offset = (tile_w // 2) if (by // tile_h) % 2 else 0
        for bx in range(-tile_w, w + tile_w, tile_w):
            bx0 = bx + offset
            tint = noisy(color, jitter)
            for y in range(by, min(by + tile_h - 1, h)):
                for x in range(bx0, min(bx0 + tile_w - 1, w)):
                    if 0 <= x < w and 0 <= y < h:
                        px[x, y] = noisy(tint, 6)
    return img


def concrete(size, base):
    img = Image.new("RGB", (size, size), base)
    px = img.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = noisy(base, 14)
    # редкие тёмные потёки/пятна
    for _ in range(size // 2):
        x = random.randint(0, size - 1)
        y = random.randint(0, size - 1)
        px[x, y] = noisy((base[0] - 30, base[1] - 30, base[2] - 30), 8)
    return img


def platform_floor(size):
    """Гранитный пол платформы — крупные плиты."""
    img = Image.new("RGB", (size, size), (60, 60, 66))
    px = img.load()
    half = size // 2
    tones = [(120, 118, 124), (108, 104, 112)]
    for i, (ox, oy) in enumerate([(0, 0), (half, 0), (0, half), (half, half)]):
        base = tones[(i + i // 2) % 2]
        for y in range(oy + 1, oy + half - 1):
            for x in range(ox + 1, ox + half - 1):
                px[x, y] = noisy(base, 12)
    return img


def rail_bed(size):
    """Полоса пути: шпалы, балласт, две рельсы."""
    img = Image.new("RGB", (size, size), (44, 40, 38))
    px = img.load()
    # балласт (щебень)
    for y in range(size):
        for x in range(size):
            px[x, y] = noisy((70, 66, 62), 22)
    # шпалы поперёк (тёмное дерево)
    for y in range(0, size, 8):
        for yy in range(y, min(y + 4, size)):
            for x in range(size):
                px[x, yy] = noisy((58, 40, 28), 8)
    # две рельсы вдоль (сталь)
    for rx in (size // 3, size - size // 3):
        for x in range(rx - 1, rx + 1):
            for y in range(size):
                px[x % size, y] = noisy((150, 150, 158), 10)
    return img


def cab_panel(w, h):
    """Пульт машиниста: тёмная панель с ребром сверху."""
    img = Image.new("RGB", (w, h), (34, 36, 40))
    px = img.load()
    for y in range(h):
        for x in range(w):
            px[x, y] = noisy((40, 42, 48), 6)
    # светлое ребро/подсветка сверху
    for y in range(0, max(2, h // 12)):
        for x in range(w):
            px[x, y] = noisy((90, 96, 110), 6)
    # заклёпки
    for x in range(4, w, 12):
        for y in (3, h - 4):
            if 0 <= y < h:
                px[x, y] = (150, 150, 160)
    return img


def metal(size, base):
    img = Image.new("RGB", (size, size), base)
    px = img.load()
    for y in range(size):
        shade = int(8 * ((y / size) - 0.5))
        for x in range(size):
            c = (base[0] + shade, base[1] + shade, base[2] + shade)
            px[x, y] = noisy(c, 6)
    return img


# --- станция: кремовая керамическая плитка ---
save(tiled_bricks(64, 16, 8, (206, 198, 176), (120, 112, 96)), "station_tile.png")
# --- тоннель: тёмный бетон ---
save(concrete(64, (58, 60, 64)), "tunnel_wall.png")
# --- пол платформы ---
save(platform_floor(64), "platform_floor.png")
# --- путь ---
save(rail_bed(64), "rail_bed.png")
# --- пульт кабины ---
save(cab_panel(128, 48), "cab_panel.png")
# --- корпус вагона (металл) ---
save(metal(32, (150, 60, 55)), "train_body.png")
# --- край платформы (жёлтая линия) ---
edge = Image.new("RGB", (32, 8), (150, 150, 150))
epx = edge.load()
for x in range(32):
    for y in range(8):
        epx[x, y] = noisy((210, 180, 40) if y < 4 else (90, 90, 96), 8)
save(edge, "platform_edge.png")

print("done")
