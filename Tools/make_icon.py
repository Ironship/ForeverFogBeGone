#!/usr/bin/env python3
"""Draw the addon's icon, for the minimap and for the download page.

    python Tools/make_icon.py            # write the files
    python Tools/make_icon.py --preview  # also a strip at the sizes it is seen at

Two things come out of one drawing:

    icon.tga                            64x64, what the minimap button shows
    curseforge/foreverfogbegone-400.png 400x400, the project avatar

It is drawn at 1024 and shrunk, because the minimap shows it at about twenty
pixels across and anything drawn at that size directly turns to porridge.
Everything about the design is a consequence of those twenty pixels:

  - a dark disc, so it reads against a snowfield and against a night sky;
  - three fog bands with hard white cores, because a soft gradient at twenty
    pixels is a grey smudge;
  - one diagonal stroke, the only shape that still says "no" when it is four
    pixels wide -- and thin enough that the fog is still visible under it,
    since a stroke that covers the subject says "no" to nothing in particular;
  - a rim drawn as one ring with a highlight faded into it, not two arcs, which
    met at a seam you could see.

The TGA is 32-bit uncompressed with an alpha channel, which is what the client
reads, and 64 is a power of two, which it insists on.
"""

import pathlib
import sys
from PIL import Image, ImageDraw, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent.parent
BIG = 1024
S = BIG / 64.0   # everything below is in 64-pixel units, scaled up to draw


def disc(size):
    """The dark round plate the rest sits on."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pad = 0.8 * S
    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        gd.line([(0, y), (size, y)],
                fill=(int(30 + 26 * (1 - t)), int(42 + 30 * (1 - t)), int(62 + 34 * (1 - t)), 255))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([pad, pad, size - pad, size - pad], fill=255)
    img.paste(grad, (0, 0), mask)

    # One ring, and a highlight faded in over its upper half with a gradient
    # mask -- two arcs butted together showed their joins at every size.
    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([pad, pad, size - pad, size - pad],
                                 outline=(96, 124, 162, 255), width=int(2.0 * S))
    shine = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shine).ellipse([pad, pad, size - pad, size - pad],
                                  outline=(186, 214, 246, 255), width=int(2.0 * S))
    fade = Image.new("L", (size, size), 0)
    fd = ImageDraw.Draw(fade)
    for y in range(size):
        fd.line([(0, y), (size, y)], fill=max(0, int(255 * (1 - y / (size * 0.62)))))
    ring.paste(shine, (0, 0), fade)
    return Image.alpha_composite(img, ring)


def fog(size, cold=False):
    """Three bands: a soft halo for body, a hard core so it survives shrinking."""
    halo = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    bands = [
        (25 * S, 13 * S, 51 * S, 4.6 * S, 190),
        (35 * S, 9 * S, 55 * S, 5.8 * S, 225),
        (45 * S, 15 * S, 49 * S, 6.6 * S, 250),
    ]
    for y, x0, x1, thickness, alpha in bands:
        hd.rounded_rectangle([x0, y - thickness / 2, x1, y + thickness / 2],
                             radius=thickness / 2,
                             fill=(150, 176, 206, alpha) if cold else (206, 226, 246, alpha))
    halo = halo.filter(ImageFilter.GaussianBlur(radius=1.3 * S))
    core = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cd = ImageDraw.Draw(core)
    for y, x0, x1, thickness, alpha in bands:
        cd.rounded_rectangle([x0 + 1.6 * S, y - thickness / 3.2, x1 - 1.6 * S, y + thickness / 3.2],
                             radius=thickness / 3.2,
                             fill=(198, 214, 232, 255) if cold else (255, 255, 255, 255))
    return Image.alpha_composite(halo, core)


def slash(size):
    """The stroke that turns a picture of fog into a picture of no fog."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    a, b = (16 * S, 15 * S), (48 * S, 49 * S)
    d.line([a, b], fill=(26, 10, 10, 200), width=int(6.6 * S))    # outline, for contrast on white
    d.line([a, b], fill=(226, 66, 52, 255), width=int(4.2 * S))
    d.line([(a[0] - 0.8 * S, a[1] + 0.8 * S), (b[0] - 0.8 * S, b[1] + 0.8 * S)],
           fill=(255, 150, 132, 170), width=int(1.1 * S))
    return layer


def build(size, struck=True):
    """struck: the sign with the stroke through it -- the fog is gone.

    Without it the same picture says the opposite: the fog is there. The
    button swaps between the two, because greying one icon out to mean "off"
    took the red stroke -- the only part that carries the meaning -- and turned
    it into another grey bar. Seen in the game at twenty pixels, next to
    Blizzard's own saturated buttons, it read as a disabled control.
    """
    img = disc(size)
    img = Image.alpha_composite(img, fog(size, cold=not struck))
    if struck:
        img = Image.alpha_composite(img, slash(size))
    return img


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
        strip = Image.new("RGBA", (2 * (sum(sizes) + 20 * len(sizes)), 80), (70, 90, 60, 255))
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
