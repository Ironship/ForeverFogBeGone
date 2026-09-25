#!/usr/bin/env python3
"""Export the approved PNG artwork as game-ready TGA; --preview shows small sizes.

Requires Pillow. Source artwork lives beside this script.
"""
import pathlib
import sys
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent.parent
BIG = 1024


def build(size, struck=True):
    source = "icon-source.png" if struck else "icon-fog-source.png"
    with Image.open(pathlib.Path(__file__).with_name(source)) as image:
        assert image.width == image.height, "Expected square artwork"
        return image.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)


def main():
    big = build(BIG)
    tga = big.resize((64, 64), Image.LANCZOS)
    tga.save(HERE / "icon.tga")

    # The other state: fog, unstruck.
    foggy = build(BIG, struck=False)
    foggy.resize((64, 64), Image.LANCZOS).save(HERE / "icon-fog.tga")

    page = HERE / "curseforge"
    page.mkdir(exist_ok=True)
    big.resize((400, 400), Image.LANCZOS).save(page / "foreverfogbegone-400.png")
    tga.save(page / "foreverfogbegone-64.png")

    if "--preview" in sys.argv:
        # The sizes it is actually seen at: the minimap icon is about 20.
        sizes = [64, 32, 20, 16]
        strip = Image.new("RGBA", (2 * (sum(sizes) + 20 * len(sizes)) + 40, 80), (70, 90, 60, 255))
        x = 10
        for source in (big, foggy):
            for s in sizes:
                small = source.resize((s, s), Image.LANCZOS)
                strip.paste(small, (x, (80 - s) // 2), small)
                x += s + 20
            x += 30
        strip.resize((strip.width * 3, strip.height * 3), Image.NEAREST).save(page / "preview-sizes.png")
        print("preview: %s" % (page / "preview-sizes.png"))

    for p in (HERE / "icon.tga", HERE / "icon-fog.tga", page / "foreverfogbegone-400.png"):
        print("%-44s %6.1f kB" % (p.relative_to(HERE), p.stat().st_size / 1024))
    head = (HERE / "icon.tga").read_bytes()[:18]
    print("TGA: type %d (2 = uncompressed truecolour), %d bits, %dx%d" % (
        head[2], head[16], head[12] | head[13] << 8, head[14] | head[15] << 8))


if __name__ == "__main__":
    main()
