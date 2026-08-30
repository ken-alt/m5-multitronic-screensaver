//
//  M5PanelView.m
//  M-5 Multitronic screensaver
//

#import "M5PanelView.h"

#pragma mark - Palette

// Sampled from the M-5 readout panel. 1960s Technicolor pushes everything
// warm, so the greens sit yellow and the reds sit orange.
typedef struct { CGFloat r, g, b; CGFloat weight; } M5Color;

static const M5Color kPalette[] = {
    { 0.620, 0.839, 0.235, 1.00 },   // lime
    { 0.784, 0.847, 0.243, 0.85 },   // yellow-green
    { 0.267, 0.745, 0.290, 0.70 },   // green
    { 0.878, 0.729, 0.188, 0.95 },   // amber
    { 0.886, 0.627, 0.157, 0.85 },   // gold
    { 0.902, 0.502, 0.149, 0.90 },   // orange
    { 0.863, 0.282, 0.157, 0.80 },   // red-orange
    { 0.769, 0.157, 0.118, 0.65 },   // deep red
    { 0.235, 0.784, 0.706, 0.18 },   // teal (rare)
};
static const int kPaletteCount = (int)(sizeof(kPalette) / sizeof(kPalette[0]));

#pragma mark - Bar model

typedef NS_ENUM(int, M5Phase) {
    M5PhaseGrow = 0,
    M5PhaseHold,
    M5PhaseLeave,
    M5PhaseGap
};

typedef NS_ENUM(int, M5Leave) {
    M5LeaveRetract = 0,   // shrinks back into its anchor
    M5LeaveFade,          // dims out at full length
    M5LeaveCut            // snaps off
};

typedef struct {
    CGFloat  x, y;        // anchor point (the end the bar grows from)
    int      cell;        // occupied grid cell, -1 when free
    BOOL     vertical;
    int      dir;         // +1 / -1 growth direction
    CGFloat  maxLen;
    CGFloat  thickness;
    int      colorIndex;
    CGFloat  vignette;    // edge falloff, baked in at spawn

    M5Phase  phase;
    M5Leave  leaveStyle;
    double   t;           // seconds elapsed in current phase
    double   growDur, holdDur, leaveDur, gapDur;

    // Hold-phase modulation
    BOOL     flickers;    // hard on/off stutter
    BOOL     breathes;    // slow smooth pulse
    double   modRate;
    double   modPhase;
} M5Bar;

#pragma mark -

@implementation M5PanelView {
    M5Bar       *_bars;
    NSUInteger   _barCount;

    BOOL        *_cellUsed;
    NSInteger    _cols, _rows;
    CGFloat      _cellW, _cellH;
    CGFloat      _originX, _originY;

    CGFloat      _unit;       // base thickness unit
    NSTimeInterval _lastTime;
    CGFloat      _invHalfW, _invHalfH;
}

#pragma mark - Random helpers

static inline double frand(void) {
    return (double)arc4random() / (double)UINT32_MAX;
}

static inline double frange(double lo, double hi) {
    return lo + frand() * (hi - lo);
}

static int pickColor(void) {
    static CGFloat total = 0;
    if (total == 0) {
        for (int i = 0; i < kPaletteCount; i++) total += kPalette[i].weight;
    }
    CGFloat r = (CGFloat)frand() * total;
    for (int i = 0; i < kPaletteCount; i++) {
        r -= kPalette[i].weight;
        if (r <= 0) return i;
    }
    return 0;
}

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (!self) return nil;

    [self setAnimationTimeInterval:1.0 / 60.0];
    self.wantsLayer = YES;
    _lastTime = 0;
    [self buildLayoutForSize:frame.size isPreview:isPreview];
    return self;
}

- (void)dealloc
{
    free(_bars);
    free(_cellUsed);
}

- (BOOL)isOpaque { return YES; }
- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow *)configureSheet { return nil; }

#pragma mark - Layout

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self buildLayoutForSize:newSize isPreview:[self isPreview]];
}

- (void)buildLayoutForSize:(NSSize)size isPreview:(BOOL)isPreview
{
    if (size.width < 8 || size.height < 8) return;

    CGFloat minDim = MIN(size.width, size.height);

    // A loose grid the bars snap to; the prop reads as a rough matrix
    // rather than free scatter.
    _cellH = MAX(isPreview ? 9.0 : 34.0, minDim / (isPreview ? 13.0 : 21.0));
    _cellW = _cellH * 1.15;

    _cols = MAX(4, (NSInteger)floor(size.width  / _cellW));
    _rows = MAX(4, (NSInteger)floor(size.height / _cellH));

    // Centre the grid so the margins match on both sides.
    _originX = (size.width  - _cols * _cellW) * 0.5;
    _originY = (size.height - _rows * _cellH) * 0.5;

    _unit = MAX(isPreview ? 1.2 : 2.8, minDim / 225.0);

    _invHalfW = 2.0 / MAX(1.0, size.width);
    _invHalfH = 2.0 / MAX(1.0, size.height);

    free(_cellUsed);
    _cellUsed = calloc((size_t)(_cols * _rows), sizeof(BOOL));

    // Sparse: the panel is mostly black, with a couple dozen live bars.
    NSUInteger want = (NSUInteger)((_cols * _rows) * 0.060);
    want = MAX(8, MIN(want, 80));

    free(_bars);
    _barCount = want;
    _bars = calloc(want, sizeof(M5Bar));

    for (NSUInteger i = 0; i < _barCount; i++) {
        _bars[i].cell = -1;
        [self respawnBar:&_bars[i]];
        // Stagger the initial state so nothing starts in lockstep.
        _bars[i].phase = (M5Phase)(arc4random_uniform(4));
        _bars[i].t     = frand() * 1.4;
    }
}

#pragma mark - Bar spawning

- (void)releaseCell:(int)cell
{
    if (cell >= 0 && cell < _cols * _rows) _cellUsed[cell] = NO;
}

- (int)claimFreeCell
{
    NSInteger total = _cols * _rows;
    if (total <= 0) return -1;
    for (int attempt = 0; attempt < 40; attempt++) {
        int c = (int)arc4random_uniform((uint32_t)total);
        if (!_cellUsed[c]) { _cellUsed[c] = YES; return c; }
    }
    return -1;
}

- (void)respawnBar:(M5Bar *)bar
{
    NSRect bounds = self.bounds;
    [self releaseCell:bar->cell];

    int cell = [self claimFreeCell];
    bar->cell = cell;

    NSInteger cx = (cell >= 0) ? (cell % _cols) : (NSInteger)arc4random_uniform((uint32_t)_cols);
    NSInteger cy = (cell >= 0) ? (cell / _cols) : (NSInteger)arc4random_uniform((uint32_t)_rows);

    // Snap to the grid, then jitter a little so it doesn't read as graph paper.
    bar->x = _originX + (cx + 0.5) * _cellW + frange(-0.16, 0.16) * _cellW;
    bar->y = _originY + (cy + 0.5) * _cellH + frange(-0.16, 0.16) * _cellH;

    // The prop is mostly upright bars with a scattering of horizontals.
    bar->vertical = (frand() < 0.72);

    CGFloat span = bar->vertical ? _cellH : _cellW;
    CGFloat cells;
    double roll = frand();
    if (roll < 0.26)      cells = frange(0.95, 1.70);   // stub
    else if (roll < 0.70) cells = frange(2.00, 3.80);   // medium
    else                  cells = frange(4.20, 7.60);   // long stroke

    // The uprights run noticeably longer than the horizontals.
    if (bar->vertical) cells *= 1.40;
    CGFloat wantLen = span * cells;

    // Grow towards whichever side has the room. Without this, long bars
    // that spawn near an edge just get clamped back into stubs.
    CGFloat roomPos = bar->vertical ? NSHeight(bounds) - bar->y
                                    : NSWidth(bounds)  - bar->x;
    CGFloat roomNeg = bar->vertical ? bar->y : bar->x;
    if (roomPos >= wantLen && roomNeg >= wantLen) {
        bar->dir = (frand() < 0.5) ? 1 : -1;
    } else {
        bar->dir = (roomPos >= roomNeg) ? 1 : -1;
    }

    CGFloat limit = (bar->dir > 0 ? roomPos : roomNeg) - _unit * 2.0;
    bar->maxLen = MIN(wantLen, MAX(span * 0.5, limit));

    // Bake in the CRT edge falloff once, rather than compositing a
    // full-screen gradient every frame (that cost ~70ms at 2560x1600).
    CGFloat nx = (bar->x - NSMidX(bounds)) * _invHalfW;
    CGFloat ny = (bar->y - NSMidY(bounds)) * _invHalfH;
    CGFloat r2 = MIN(1.0, (nx * nx + ny * ny) * 0.75);
    bar->vignette = 1.0 - 0.45 * r2 * r2;

    bar->thickness  = _unit * frange(0.88, 1.40);
    bar->colorIndex = pickColor();

    // 25% snap on instantly — the readout should feel switched, not drawn.
    bar->growDur  = (frand() < 0.25) ? frange(0.03, 0.10) : frange(0.28, 0.90);
    bar->holdDur  = frange(1.20, 6.50);
    bar->leaveDur = frange(0.20, 0.75);
    bar->gapDur   = frange(0.60, 4.80);

    double leaveRoll = frand();
    bar->leaveStyle = (leaveRoll < 0.40) ? M5LeaveRetract
                    : (leaveRoll < 0.80) ? M5LeaveFade
                                         : M5LeaveCut;

    bar->flickers = (frand() < 0.22);
    bar->breathes = (!bar->flickers && frand() < 0.30);
    bar->modRate  = bar->flickers ? frange(1.4, 4.5) : frange(0.18, 0.60);
    bar->modPhase = frand() * M_PI * 2.0;

    bar->phase = M5PhaseGrow;
    bar->t     = 0;
}

#pragma mark - Animation

static inline double easeOutCubic(double p) {
    double q = 1.0 - p;
    return 1.0 - q * q * q;
}

- (void)animateOneFrame
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    double dt = (_lastTime > 0) ? (now - _lastTime) : (1.0 / 60.0);
    _lastTime = now;
    if (dt > 0.25) dt = 0.25;   // don't lurch after a stall

    for (NSUInteger i = 0; i < _barCount; i++) {
        M5Bar *b = &_bars[i];
        b->t += dt;
        switch (b->phase) {
            case M5PhaseGrow:
                if (b->t >= b->growDur) { b->t -= b->growDur; b->phase = M5PhaseHold; }
                break;
            case M5PhaseHold:
                if (b->t >= b->holdDur) { b->t -= b->holdDur; b->phase = M5PhaseLeave; }
                break;
            case M5PhaseLeave: {
                double d = (b->leaveStyle == M5LeaveCut) ? 0.0 : b->leaveDur;
                if (b->t >= d) {
                    b->t -= d;
                    b->phase = M5PhaseGap;
                    // Free the slot as soon as it goes dark so others can use it.
                    [self releaseCell:b->cell];
                    b->cell = -1;
                }
                break;
            }
            case M5PhaseGap:
                if (b->t >= b->gapDur) [self respawnBar:b];
                break;
        }
    }

    [self setNeedsDisplay:YES];
}

// Current drawn length and brightness for a bar, 0 length = don't draw.
static void barState(const M5Bar *b, CGFloat *outLen, CGFloat *outAlpha)
{
    CGFloat len = 0, alpha = 0;
    switch (b->phase) {
        case M5PhaseGrow:
            len   = b->maxLen * (CGFloat)easeOutCubic(b->growDur > 0 ? MIN(1.0, b->t / b->growDur) : 1.0);
            alpha = 1.0;
            break;
        case M5PhaseHold: {
            len   = b->maxLen;
            alpha = 1.0;
            if (b->flickers) {
                double s = sin(b->modPhase + b->t * b->modRate * M_PI * 2.0);
                alpha = (s > -0.35) ? 1.0 : 0.10;      // hard stutter, mostly on
            } else if (b->breathes) {
                double s = sin(b->modPhase + b->t * b->modRate * M_PI * 2.0);
                alpha = 0.72 + 0.28 * (CGFloat)((s + 1.0) * 0.5);
            }
            break;
        }
        case M5PhaseLeave: {
            double p = (b->leaveDur > 0) ? MIN(1.0, b->t / b->leaveDur) : 1.0;
            if (b->leaveStyle == M5LeaveRetract) {
                len = b->maxLen * (CGFloat)(1.0 - easeOutCubic(p));
                alpha = 1.0;
            } else if (b->leaveStyle == M5LeaveFade) {
                len = b->maxLen;
                alpha = (CGFloat)(1.0 - p);
            } else {
                len = 0; alpha = 0;                     // cut
            }
            break;
        }
        case M5PhaseGap:
            len = 0; alpha = 0;
            break;
    }
    *outLen = len;
    *outAlpha = alpha;
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)rect
{
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect b = self.bounds;

    // The panel face.
    CGContextSetGrayFillColor(ctx, 0.016, 1.0);
    CGContextFillRect(ctx, b);

    if (!_bars) return;

    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetBlendMode(ctx, kCGBlendModePlusLighter);

    // Each bar is a wide dim bloom, a tighter halo, and the saturated core.
    // plusLighter is saturating addition, so the three are order-independent
    // and can all be laid down in one visit to the bar — no need for three
    // passes over the whole array just to get the core on top.
    const CGFloat widthMul[3] = { 4.6, 2.5, 1.0 };
    const CGFloat alphaMul[3] = { 0.115, 0.25, 0.95 };

    for (NSUInteger i = 0; i < _barCount; i++) {
        const M5Bar *bar = &_bars[i];
        CGFloat len, alpha;
        barState(bar, &len, &alpha);
        if (len <= 0.5 || alpha <= 0.01) continue;

        // Pull the bloom in on stubby bars so they read as short strokes
        // rather than glowing dots.
        CGFloat tight = MIN(1.0, len / (bar->thickness * 9.0));

        const M5Color c = kPalette[bar->colorIndex];
        CGFloat a = alpha * bar->vignette;
        CGFloat x2 = bar->x + (bar->vertical ? 0 : len * bar->dir);
        CGFloat y2 = bar->y + (bar->vertical ? len * bar->dir : 0);

        for (int pass = 0; pass < 3; pass++) {
            CGContextSetRGBStrokeColor(ctx, c.r, c.g, c.b, a * alphaMul[pass]);
            CGContextSetLineWidth(ctx,
                bar->thickness * (1.0 + (widthMul[pass] - 1.0) * tight));
            CGContextMoveToPoint(ctx, bar->x, bar->y);
            CGContextAddLineToPoint(ctx, x2, y2);
            CGContextStrokePath(ctx);
        }
    }

    CGContextSetBlendMode(ctx, kCGBlendModeNormal);
}

@end
