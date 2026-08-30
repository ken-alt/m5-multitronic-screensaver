# M-5 Multitronic

A macOS screensaver based on the M-5 computer readout panel from *Star Trek*
TOS, "The Ultimate Computer" (S2E24) — the black panel of short coloured light
bars that blink, extend and retract while the machine thinks.

## What it does

Bars sit on a jittered grid over a black field. Each one grows from an anchor
point (some ease in, ~25% snap on instantly), holds for 1.2–6.5s — sometimes
with a hard stutter, sometimes with a slow breathing pulse — then either
retracts, fades, or cuts out. After a dark gap it respawns somewhere else in a
new colour. About 72% are upright, the rest horizontal, matching the prop; the
uprights run 40% longer. A bar grows towards whichever side has room, so long
strokes aren't clipped back into stubs when they spawn near an edge.

Palette sampled from the episode: lime, yellow-green, green, amber, gold,
orange, red-orange, deep red, and an occasional teal. The 1960s Technicolor
push means the greens sit yellow and the reds sit orange.

Each bar is drawn in three additive passes — a wide dim bloom, a tighter halo,
and the saturated core — with the bloom pulled in on short bars so stubs read
as strokes rather than glowing dots. A per-bar edge falloff stands in for a
CRT vignette.

![](still-a.png)

## Install

```bash
./build.sh && cp -R "build/M-5 Multitronic.saver" ~/"Library/Screen Savers/"
```

Then pick it in System Settings → Screen Saver ("M-5 Multitronic", under Other).

Run the same line again to reinstall after editing `src/M5PanelView.m`. If the
screensaver is already selected, `killall legacyScreenSaver` afterwards so macOS
drops the cached bundle.

To remove: `rm -rf ~/"Library/Screen Savers/M-5 Multitronic.saver"`

## Knobs

All in `src/M5PanelView.m`:

| What | Where |
|---|---|
| Colours and their relative frequency | `kPalette` |
| How many bars are alive at once | `want = (_cols * _rows) * 0.060` in `buildLayoutForSize:` |
| Grid coarseness | `_cellH` in `buildLayoutForSize:` |
| Bar thickness | `_unit` in `buildLayoutForSize:` |
| Length distribution (stub / medium / long) | the `roll` block in `respawnBar:` |
| Timing — grow, hold, leave, gap | the `frange(...)` durations in `respawnBar:` |
| Stutter / pulse frequency | `flickers`, `breathes`, `modRate` in `respawnBar:` |
| Glow strength and spread | `widthMul` / `alphaMul` in `drawRect:` |
| Vertical vs horizontal mix | `bar->vertical = (frand() < 0.72)` |

## Performance

CPU rasterisation of `drawRect:`, on a 1.4 GHz Core i5-8257U:

| Resolution | ms/frame |
|---|---|
| 1440×900 | 2.9 |
| 2560×1600 | 8.3 |
| 3360×2100 | 14.2 |

The first version composited a full-screen radial gradient for the vignette,
which cost ~72 ms/frame at 2560×1600 on its own. Baking the falloff into each
bar's alpha at spawn time gives the same look for free.

Cost scales with lit area, so it's the long bars and the width of the outer
bloom (`widthMul[0]`) that dominate — lengthen the bars much further and that
is the first thing to trim.

The three strokes that make up a bar used to be drawn as three passes over the
whole array, so that the core landed on top. `plusLighter` is saturating
addition and therefore order-independent, so they are now emitted in one visit
per bar — same pixels, a third of the per-bar state evaluation.

## Notes

`build.sh` builds for the host architecture. Screensaver bundles must match the architecture of the host process, and
Rosetta does not apply — an Intel `.saver` will not load into the arm64
`legacyScreenSaver` on Apple Silicon, it just won't show up in the list.

Moving to an Apple Silicon Mac: copy this folder over, install the Command Line
Tools (`xcode-select --install`) if they aren't there, and run `./build.sh`.
It detects `arm64` and sets the deployment floor to 11.0 automatically.

The animation is original code; only the look is referenced. Star Trek is a
trademark of CBS Studios Inc.; this project is unaffiliated fan work and ships
no material from the show.

## License

MIT — see [LICENSE](LICENSE).
