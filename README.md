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

![](docs/m5-multitronic.png)

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

**Remaster** is an emissive readout: lit amber numerals on dark drums. There is
no wheel to turn and no lamp to switch, so digits translate rather than rotate,
and the clock module drops the light switch entirely.

![](docs/chronometer-remaster.png)

The shading runs opposite ways for the same reason. The dark drum is lit from
the slot edges, brightest top and bottom. The pale drum has no lamp of its own
— light enters from behind the mask, strongest along the top — so it darkens
towards the bottom, and the shading multiplies over the numerals because they
are printed on that surface rather than glowing through it.

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

The single biggest cost by a wide margin is a **full-screen radial gradient**.
One as a vignette measured ~72 ms/frame alone. Later the gloss backdrop and the
cover glass reintroduced three of them between them, and the clock saver ran at
**341 ms/frame**. Both layers are fixed for a given size, so they are rendered
once and blitted, taking that saver to ~22 ms. If something is suddenly slow,
look for a gradient covering the whole screen before anything else.

### What caching does and does not fix

Caching pays when it replaces per-pixel *computation* with an **opaque copy**.
The backdrop and cover glass are the case in point: full-screen radial
gradients became a straight blit, and a saver went from 341 ms to 22 ms.

Caching does not pay when the result still has to be **alpha-composited** over
the same area. Compositing a large translucent image costs about what
generating it did, because both are fill-rate bound and neither is a memcpy.
This was measured three separate ways — via `CGLayer`, per-window bezels, and
finally the whole static window furniture as `CGImage` — and every one landed
inside noise or under 8%.

That is the ceiling, not a missing optimisation. Screen-clean figures at
2560×1600, against a 16.67 ms budget:

| Saver | ms/frame |
|---|---|
| M-5 Multitronic | 6.5 |
| Clock — Classic | 19.0 |
| Clock — Remaster | 19.4 |
| Chronometer — Classic | 60.2 |
| Chronometer — Remaster | 59.9 |

Classic and Remaster cost the same within noise, which contradicts an
assumption held for several rounds that the Classic's opaque mask made it the
expensive one.

### Measure before you optimise

The chronometers were assumed to be slow because their apertures are ~6.3× the
area of the clock module's. Removing every window — bezels, drum faces, digits
and all the lighting passes — took a 59.7 ms frame only to 49.5 ms. The windows
were never the problem.

The cost was one call: the unit plate's blurred drop shadow, **32 ms of 59**.
CoreGraphics shadows scale with area times blur radius, and blur here is
proportional to plate height, so the chronometer's 1843×590 plate costs roughly
nine times the clock module's. The plate never changes — it only drifts — so it
is now rendered once and blitted, taking the chronometers to ~44 ms.

Note the cached blit still costs ~17 ms of that: the image carries alpha for
the shadow margin, so compositing it is fill-rate bound in the same way. Only
opaque copies are genuinely cheap.

Getting the chronometers inside budget means moving the compositing to the GPU
— a `CAMetalLayer` returned from the view's backing layer, since a
`ScreenSaverView` subclass cannot use `MTKView`. Rectangular clipping instead
of rounded-path clipping was worth about 1.5 ms and is already in.

Benchmarks are meaningless on a loaded machine. Check `uptime` first — a
background encode moved these numbers by 7×.

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
