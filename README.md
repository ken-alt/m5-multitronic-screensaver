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

**[Download M-5 Multitronic with Clock - Classic.saver.zip](https://github.com/ken-alt/m5-multitronic-screensaver/raw/main/dist/M-5%20Multitronic%20with%20Clock%20-%20Classic.saver.zip)** · 187 KB

### M-5 Multitronic with Clock - Remaster

![](docs/clock-remaster.png)

The field with the clock module as the remastered episode shows it: amber numerals lit from within, on black.

**[Download M-5 Multitronic with Clock - Remaster.saver.zip](https://github.com/ken-alt/m5-multitronic-screensaver/raw/main/dist/M-5%20Multitronic%20with%20Clock%20-%20Remaster.saver.zip)** · 186 KB

### TOS Chronometer - Classic

![](docs/chronometer-classic.png)

Stardate and ship's time, original prop.

**[Download TOS Chronometer - Classic.saver.zip](https://github.com/ken-alt/m5-multitronic-screensaver/raw/main/dist/TOS%20Chronometer%20-%20Classic.saver.zip)** · 134 KB

### TOS Chronometer - Remaster

![](docs/chronometer-remaster.png)

Stardate and ship's time, remastered finish.

**[Download TOS Chronometer - Remaster.saver.zip](https://github.com/ken-alt/m5-multitronic-screensaver/raw/main/dist/TOS%20Chronometer%20-%20Remaster.saver.zip)** · 122 KB


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
A digit does not travel at all: the old numeral fades out as the new one
comes up in its place, drawn additively, because that is what a lit display
does. An earlier version slid them through the aperture, which still read as
a drum turning past a window — the one mechanism this era does not have.

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
sections cannot disagree on size, or two when set to 24-hour time. Every character rides its own wheel, and the
wheels are the same width, so the punctuation gets a full cell.

| | |
|---|---|
| ![](docs/clock-classic.png) | ![](docs/clock-remaster.png) |
| Classic | Remaster |


## Stardate

The chronometers show a stardate because it is fun, not because it is
authoritative. TOS stardates were arbitrary by design — the writers' guide told
writers to pick any four digits and a decimal, and the show contradicts itself
constantly. There is nothing to derive.

So this uses the convention the later series settled on: **1000 units to the
year**, counted from 1000.0 at 2020-01-01 UTC.

```
today    7667.5
+1 day   7670.2
+1 year  8667.5
```

Note what that means on screen: the tenth advances roughly **every 53 minutes**.
Watch the panel for a minute and the stardate will not move. That is correct
rather than broken — it is a date, sampled once a frame like everything else,
and a date does not tick.

An earlier version ran at 1.0/day, which put the same digit at one change every
2.4 hours. Both are effectively static to a viewer; the current rate is at least
a convention someone else chose. Making it visibly tick would mean inventing a
rate from nothing, which buys motion at the cost of the only thing about the
number that is defensible.

It never sets the readout's width, incidentally — the shipboard reading is
eight characters against the stardate's six, so the shared digit pitch is
always driven by the clock beside it.


## References

The proportions, palette and lighting here were measured off two sources
rather than guessed. Neither is reproduced in this repository — they belong to
their rights holders — so they are cited instead:

- **The original prop**, a countdown panel: two windows of dark numerals on
  pale drums, red indicator lamps captioned `HRS`/`MIN` and `SEC`, and two bat
  toggles labelled *light switch* and *clock switch* below. One switch is kept,
  centred, on the chronometer panel; the clock module goes without, having no
  room for it beside three readouts.
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


## "macOS cannot verify this screensaver"

Expected, and not a sign anything is wrong with the download. These bundles are
**ad-hoc signed**: the signature proves the files have not been altered since
they were built, but it carries no Apple Developer identity, so Gatekeeper has
no one to attribute them to. Your browser also tags anything downloaded with a
quarantine flag, and that flag is what raises the dialog.

Clear it and the saver runs normally:

```bash
xattr -dr com.apple.quarantine ~/Library/Screen\ Savers/*.saver
```

The bundle is unchanged by this — `codesign --verify --deep --strict` still
passes afterwards. You are telling macOS you trust the source, not disabling a
check on the file's integrity.

Making the dialog go away properly means a Developer ID certificate and
notarisation, which needs a paid Apple Developer Program membership. For a free
MIT screensaver that is a real cost for a dialog you see once, so it is not done
here. Anyone who would rather not trust a stranger's binary can build from
source instead — see **Install** above; it needs only Xcode.

## Fonts

`DigitFacePreference` resolves DIN Condensed Bold → SF Condensed Bold → the
built-in drum vectors in `src/DrumDigits.swift`. Everything in that chain ships
with macOS, so nothing needs installing and no font is bundled.

**Never request SF by PostScript name.** CoreText silently substitutes Times
New Roman for `.SFNS-Bold` and only logs a note about it. Use
`NSFont.systemFont` with a descriptor width trait.


## Licence

MIT — see [LICENSE](LICENSE). Star Trek is a trademark of CBS Studios Inc.;
this is unaffiliated fan work and ships no material from the series.
