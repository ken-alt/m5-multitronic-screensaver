# Star Trek TOS screensavers

Five macOS screensavers built from set props in *Star Trek: The Original
Series*. All are original code and original artwork; only the look is
referenced.

| Screensaver | What it shows |
|---|---|
| **M-5 Multitronic** | the M-5 computer readout field |
| **TOS Chronometer — Remaster** | stardate and ship's time, remastered finish |
| **TOS Chronometer — Classic** | the same panel as the original prop |
| **M-5 Multitronic with Clock — Remaster** | the field with a clock module |
| **M-5 Multitronic with Clock — Classic** | the same, original-prop finish |

## Download

Each is a ready-built universal bundle. Unzip, double-click to install (or drop
into `~/Library/Screen Savers/`), then pick it in System Settings → Screen
Saver, under Other.

### M-5 Multitronic

![](docs/m5-multitronic.png)

The M-5 computer readout field on its own.

**[Download M-5 Multitronic.saver.zip](https://github.com/ken-alt/m5-multitronic-screensaver/raw/main/dist/M-5%20Multitronic.saver.zip)** · 39 KB

### M-5 Multitronic with Clock - Classic

![](docs/clock-classic.png)

The field with the clock module, built as the original prop: ink on pale wheels behind a white mask, turning on an arc.

**[Download M-5 Multitronic with Clock - Classic.saver.zip](https://github.com/ken-alt/m5-multitronic-screensaver/raw/main/dist/M-5%20Multitronic%20with%20Clock%20-%20Classic.saver.zip)** · 186 KB

### M-5 Multitronic with Clock - Remaster

![](docs/clock-remaster.png)

The field with the clock module as the remastered episode shows it: amber numerals lit from within, on black.

**[Download M-5 Multitronic with Clock - Remaster.saver.zip](https://github.com/ken-alt/m5-multitronic-screensaver/raw/main/dist/M-5%20Multitronic%20with%20Clock%20-%20Remaster.saver.zip)** · 184 KB

### TOS Chronometer - Classic

![](docs/chronometer-classic.png)

Stardate and ship's time, original prop.

**[Download TOS Chronometer - Classic.saver.zip](https://github.com/ken-alt/m5-multitronic-screensaver/raw/main/dist/TOS%20Chronometer%20-%20Classic.saver.zip)** · 134 KB

### TOS Chronometer - Remaster

![](docs/chronometer-remaster.png)

Stardate and ship's time, remastered finish.

**[Download TOS Chronometer - Remaster.saver.zip](https://github.com/ken-alt/m5-multitronic-screensaver/raw/main/dist/TOS%20Chronometer%20-%20Remaster.saver.zip)** · 122 KB

## Options

Both clock savers carry a configure sheet — the **Options…** button beside the
saver in System Settings → Screen Saver.

| | |
|---|---|
| **Time format** | 12-hour (default) or 24-hour |

A 24-hour reading has no meridiem, so that window is not merely blanked — it is
removed, and the plate narrows by exactly the window and gap that went away so
the two remaining readouts keep the margins they had. Nothing else about the
12-hour layout changes.

`hasConfigureSheet` and `configureSheet` are both present and undeprecated in
the macOS 26 SDK, and the redesigned System Settings pane still calls them, so
this needs no private API. The setting is stored through `ScreenSaverDefaults`,
which is keyed by bundle identifier — each variant therefore keeps its own.

The chronometers deliberately have no such option: the prop shows ship's time
in 24 hours with no meridiem window, and that is what they reproduce.

## Two eras of the same prop

The chronometer appears twice on screen in the series, and the remastered
episodes rebuilt it. The two are not a recolour of each other — they are
different mechanisms, and the code treats them that way through
`CounterWindow.finish`.

**Classic** is a mechanical drum counter: dark ink printed on pale wheels
behind a white mask, lit by a warm lamp above the opening. The wheels are
*reflective*, so a digit change physically rotates — the numerals travel on an
arc, vertical position following sin and apparent height following cos, and the
foreshortening is what reads as rotation rather than a card sliding past.

![](docs/chronometer-classic.png)

**Remaster** is an emissive display — amber numerals lit from within, on black.
There is no wheel, so there are no division lines and nothing for a lamp to
fall on; the cell spacing is kept only so the two eras read at the same size.
Digits translate rather than rotate, and the clock module drops the light
switch entirely, since there is no lamp to switch.

![](docs/chronometer-remaster.png)

Only the Classic is shaded at all. Its pale drum has no lamp of its own —
light enters from behind the mask, strongest along the top — so the surface
darkens towards the bottom, and the shading multiplies over the numerals
because they are printed on it rather than glowing through it. The Remaster is
its own light source, so nothing shades it.

## The clock module

A black anodised aluminium insert sunk into the gloss display, with `HRS`,
`MIN` and `SEC` engraved and ink-filled. Three drums — hours and minutes,
seconds, meridiem — sharing one digit pitch and one glyph height so the
sections cannot disagree on size. Every character rides its own wheel, and the
wheels are the same width, so the punctuation gets a full cell.

| | |
|---|---|
| ![](docs/clock-classic.png) | ![](docs/clock-remaster.png) |
| Classic | Remaster |

## References

The proportions, palette and lighting here were measured off two sources
rather than guessed. Neither is reproduced in this repository — they belong to
their rights holders — so they are cited instead:

- **The original prop**, a countdown panel: two windows of dark numerals on
  pale drums, red indicator lamps captioned `HRS`/`MIN` and `SEC`, and two bat
  toggles labelled *light switch* and *clock switch* below.
- **The remastered chronometer**, seen at about 0:46 of
  [this clip](https://www.youtube.com/watch?v=wGB9gjRnv00): amber numerals on
  gloss black behind chrome bezels, captioned `STARDATE` and `SHIPBOARD`.
- **The M-5 readout field**, at about 0:39 of
  [this clip](https://www.youtube.com/watch?v=8ixabejG0O0) — "The Ultimate
  Computer", S2E24.

What was taken from them: the bar palette (lime through deep red, plus a rare
teal — 1960s Technicolor pushes the greens yellow and the reds orange); the
window proportions and the frame being wider at the sides than top and bottom;
the lamp placement inline with the captions rather than one per window; and the
fact that the numerals carry a visible vertical falloff from the lamps.

## Install

Requires Xcode for the current SDK.

```bash
./build.sh && cp -R build/*.saver ~/"Library/Screen Savers/"
```

Then pick one in System Settings → Screen Saver, under Other. Run the same line
again to reinstall; if a saver is already selected, `killall legacyScreenSaver`
afterwards so macOS drops the cached bundle.

The bundles in `dist/` are committed build products, refreshed with:

```bash
./build.sh && rm -rf dist && mkdir dist && \
  for d in build/*.saver; do \
    ditto -c -k --sequesterRsrc --keepParent "$d" "dist/$(basename "$d").zip"; \
  done
```

`ditto` rather than `zip`: it keeps the bundle structure and the ad-hoc
signature intact through the round trip.

Builds universal (x86_64 + arm64) against the macOS 15 SDK.

**Thumbnails are not possible.** Apple provides no supported way to replace the
default screensaver thumbnail — confirmed by Apple DTS on the
[developer forums](https://developer.apple.com/forums/thread/806641) — and on
macOS 26 custom thumbnails do not display at all.

## Fonts

`DigitFacePreference` resolves DIN Condensed Bold → SF Condensed Bold → the
built-in drum vectors in `src/DrumDigits.swift`. Everything in that chain ships
with macOS, so nothing needs installing and no font is bundled.

**Never request SF by PostScript name.** CoreText silently substitutes Times
New Roman for `.SFNS-Bold` and only logs a note about it. Use
`NSFont.systemFont` with a descriptor width trait.

## The framework does not stop your saver

Apple's screen saver framework does not reliably tear a view down when the
saver is dismissed. The instance survives and `animateOneFrame` keeps being
called, burning CPU with nothing on screen. Every view here tracks its own
state through `startAnimation` / `stopAnimation` and `viewDidMoveToWindow`.

Measured on the animation callback: 17.8 µs running against 0.09 µs dismissed
on the bar field, and 140.7 µs against 0.17 µs on the retro clock. Without the
guard, that second figure runs forever.

## What actually costs time

Measured at 2560×1600 on a 1.4 GHz Core i5-8257U, against a 16.67 ms budget.

| Saver | before | after |
|---|---|---|
| M-5 Multitronic | 9.35 | **5.30** |
| Clock — Classic | 18.56 | **9.92** |
| Clock — Remaster | 17.43 | **11.75** |
| Chronometer — Classic | 51.91 | **3.68** |
| Chronometer — Remaster | 44.48 | **5.46** |

Three things account for nearly all of it.

### A cached blit must match its destination exactly

This one was worth 19 ms a frame on its own, and it hid behind a wrong
conclusion for a long time.

Cache an image, then draw it into a rect whose size differs from the image's
pixel dimensions — even by a fraction of a point — and CoreGraphics resamples
every pixel instead of copying it. The chronometer's panel is about 1.6M
pixels; blitting it cost **19.8 ms**, against 0.87 ms for the numerals it
framed. Rounding the plate and aperture rects to whole points took that same
blit to **0.86 ms**. The front tier went from 4.5 ms to 0.17 ms the same way.

Whole-point geometry is therefore load-bearing here, not tidiness. The same bug
lived in `drawUnitPlate`, whose destination was `plate.insetBy(-pad)` while its
image was rounded to integers; fixing that one line took ~5 ms off both clock
savers.

An earlier version of this file concluded that compositing a large translucent
image "costs about what generating it did" and called that the ceiling. That
was wrong. It was measuring resampling, not compositing, and the ceiling was an
artefact of the measurement.

### Full-screen radial gradients

Still the most expensive single thing CoreGraphics does here. One vignette
measured ~72 ms/frame alone; the gloss backdrop and cover glass together once
put a saver at **341 ms/frame**. Both are fixed for a given size, so they are
rendered once and blitted. If something is suddenly slow, look for a gradient
covering the whole screen before anything else.

A bottom layer that covers the frame has nothing to blend with, so it is built
**opaque** — `noneSkipFirst` rather than `premultipliedFirst`. That makes the
blit a copy rather than a four-million-pixel composite, worth ~1.5 ms.

### Build caches at device resolution

Every cache here was originally built at *point* size, so on a Retina display
it was upscaled and soft. Invisible on a smooth gradient, plainly wrong on
etched text and screw heads. `CounterChrome.pixelScale` reads the scale off the
context's own transform and `renderScaled` builds at that resolution, leaving
the drawing inside expressed in points.

### Measure, don't guess

Every time the cost of something here was assumed rather than measured, the
assumption was wrong — and expensively so:

- The chronometers were assumed slow because their apertures are ~6.3× the clock
  module's area. Removing every window took a 59.7 ms frame only to 49.5 ms.
- The cost turned out to be one call: the plate's blurred drop shadow, 32 ms of
  59. CoreGraphics shadows scale with area × blur radius.
- After caching, the digits — the only thing that actually changes — were 0.87 ms
  of a 26.5 ms frame. The panel blit was 19.8.
- A case was once built for moving to `CAMetalLayer` on the strength of a wrong
  diagnosis, and withdrawn once the frame was decomposed properly.

`M5_PROFILE=1` prints the chronometer's per-tier timings for exactly this
reason. Benchmarks are also meaningless on a loaded machine — check `uptime`
first; a background encode moved these numbers by 7×.

### How the drawing is tiered

`CounterWindow` splits into `drawBelow` (bezel and barrel), `drawDigits` (the
reading) and `drawAbove` (lamp wash, mask, gloss, inner shadow). Only the
middle changes between frames, and the burn-in wander is a *translation* of the
whole panel rather than a redraw — so the chrome is rendered once in
panel-local coordinates and blitted at the drifted origin. Every chrome routine
brackets itself in `save`/`restoreGState`, which is what lets the tiers be drawn
into separate contexts.

## A note on derived dimensions

Nearly every visual defect in this project has had the same cause: a dimension
written as its own constant when it should have been derived from the thing it
must fit. Bezel width, aperture radius, label spacing, the mask opening, roll
travel, glyph height across windows — each was two numbers that had to agree,
written separately, until one changed.

They are consolidated now: `bezelWidth` and `bezelSideWidth`, `apertureRadius`,
`labelWidth` for measuring text, mask opening from the drawn glyph height, roll
travel from aperture height. If something looks wrong, look first for two values
that must match but are stated independently.

## Licence

MIT — see [LICENSE](LICENSE). Star Trek is a trademark of CBS Studios Inc.;
this is unaffiliated fan work and ships no material from the series.
