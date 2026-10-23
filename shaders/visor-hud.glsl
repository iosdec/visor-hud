// Visor HUD: a sci-fi helmet-visor overlay for Ghostty and cmux.
// Static: angled visor frame, hexagonal shield bar, telemetry microtext, drifting
// bokeh behind the text, visor glow, scanlines, vignette.
// Reactive: plasma bolt + lock-on reticle when the cursor jumps, a hex shield
// flare when a pane gains focus, "shields down" on panes you're not in, and a
// motion tracker whose gold blip is your cursor.
// Flip the switches below, save, then run `cmux reload-config`.
// Needs `window-padding-y = 48,30` so the top bar and bottom frame sit in the padding.

#define SHOW_GLOW      1
#define SHOW_SCANLINES 1
#define SHOW_BOKEH     1
#define SHOW_TOPO      1   // holo-table contour lines behind the text
#define SHOW_DUST      1   // floating hologram particles
#define SHOW_INTERFERENCE 1 // rolling hologram band with colour fringing
#define SHOW_RINGS     1   // rotating rings around the tracker
#define SHOW_FRAME     1
#define SHOW_TEXT      1
#define SHOW_SHIELD    1
#define SHOW_TRACKER   1
#define TRACKER_LEFT   0   // 1 = bottom-left like the games (can sit over your prompt)
#define SHOW_RETICLE   1
#define SHOW_PLASMA    1
#define SHOW_FLARE     1
#define DIM_UNFOCUSED  0
// 1 = panes you're not in keep full cyan shields (only the focused pane plays the recharge)
#define SHIELDS_UP_UNFOCUSED 1
// 1 = shield level comes from the shell (~/.config/visor-hud/shield.zsh via palette 255)
#define SHELL_SHIELD   1
// If the shield bar shows at the bottom instead of the top, set this to 1.
#define FLIP_Y         0

const vec3 HUD   = vec3(0.247, 0.816, 1.000); // #3fd0ff
const vec3 GOLD  = vec3(0.961, 0.722, 0.255); // #f5b841
const vec3 ENEMY = vec3(0.898, 0.282, 0.302); // #e5484d
const vec3 ROUTE = vec3(1.000, 0.478, 0.239); // #ff7a3d holo-table route orange
const float PAD_TOP = 48.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float box(vec2 p, vec2 lo, vec2 hi) {
    vec2 s = step(lo, p) * step(p, hi);
    return s.x * s.y;
}

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

float vnoise(vec2 x) {
    vec2 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
               mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 x) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * vnoise(x); x *= 2.03; a *= 0.5; }
    return v;
}

// Distance to the nearest hex cell edge (0 on the edge).
float hexEdge(vec2 p) {
    const vec2 k = vec2(1.0, 1.7320508);
    vec2 a = mod(p, k) - k * 0.5;
    vec2 b = mod(p - k * 0.5, k) - k * 0.5;
    vec2 g = abs(dot(a, a) < dot(b, b) ? a : b);
    return 0.5 - max(dot(g, normalize(k)), g.x);
}

// ---- 3x5 bitmap font -------------------------------------------------------
int glyph(int c) {
    switch (c) {
        case 65: return 11245; // A
        case 66: return 27566; // B
        case 67: return 14627; // C
        case 68: return 27502; // D
        case 69: return 31143; // E
        case 70: return 31140; // F
        case 71: return 14699; // G
        case 72: return 23533; // H
        case 73: return 29847; // I
        case 74: return 4714; // J
        case 75: return 23469; // K
        case 76: return 18727; // L
        case 77: return 24557; // M
        case 78: return 27501; // N
        case 79: return 11114; // O
        case 80: return 27556; // P
        case 81: return 11123; // Q
        case 82: return 27565; // R
        case 83: return 14478; // S
        case 84: return 29842; // T
        case 85: return 23407; // U
        case 86: return 23402; // V
        case 87: return 23549; // W
        case 88: return 23213; // X
        case 89: return 23186; // Y
        case 90: return 29351; // Z
        case 48: return 31599; // 0
        case 49: return 11415; // 1
        case 50: return 25255; // 2
        case 51: return 25230; // 3
        case 52: return 23497; // 4
        case 53: return 31118; // 5
        case 54: return 14831; // 6
        case 55: return 29330; // 7
        case 56: return 31727; // 8
        case 57: return 31694; // 9
        case 47: return 4772; // /
        case 45: return 448; // -
        case 46: return 2; // .
        case 58: return 1040; // :
        case 37: return 21157; // %
    }
    return 0;
}

// q: position inside a 3x5 cell, y down. Returns 1 on a lit pixel.
float charPx(int c, vec2 q) {
    if (q.x < 0.0 || q.x >= 3.0 || q.y < 0.0 || q.y >= 5.0) return 0.0;
    int v = glyph(c);
    int bit = 3 * (4 - int(q.y)) + (2 - int(q.x));
    return float((v >> bit) & 1);
}

// Draws string `s` (n chars) with its top-left at `o`, pixel size `sc`.
#define TEXT(s, n, o, sc) { \
    vec2 tq = vec2(p.x - (o).x, (o).y - p.y) / (sc); \
    if (tq.y >= 0.0 && tq.y < 5.0 && tq.x >= 0.0 && tq.x < float(n) * 4.0) { \
        int ci = int(tq.x / 4.0); \
        txt = max(txt, charPx(s[ci], vec2(mod(tq.x, 4.0), tq.y))); } }

const int S_SUIT[25]  = int[](86, 73, 83, 79, 82, 32, 47, 47, 32, 73, 78, 84, 69, 82, 70, 65, 67, 69, 32, 79, 78, 76, 73, 78, 69); // VISOR // INTERFACE ONLINE
const int S_SUB[14]   = int[](47, 77, 79, 68, 32, 47, 80, 82, 68, 32, 47, 66, 65, 84);                                                   // /MOD /PRD /BAT
const int S_VISOR[20] = int[](86, 73, 83, 79, 82, 32, 83, 89, 83, 32, 47, 47, 32, 78, 79, 77, 73, 78, 65, 76);                           // VISOR SYS // NOMINAL
const int S_RANGE[9]  = int[](82, 65, 78, 71, 69, 32, 52, 48, 77);                                                                       // RANGE 40M

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    vec3 base = texture(iChannel0, uv).rgb;
    float band = 0.0;
#if SHOW_INTERFERENCE
    // A hologram interference band rolls down the screen every ~7s, fringing colours.
    float by = 1.15 - fract(iTime / 7.0) * 1.3;
    band = exp(-pow((uv.y - by) / 0.025, 2.0));
    if (band > 0.01) {
        float off = band * 2.5 / res.x * max(1.0, res.y / 900.0);
        float jit = (hash(floor(iTime * 30.0) + floor(uv.y * 120.0)) - 0.5) * band * 1.5 / res.x;
        base.r = texture(iChannel0, uv + vec2(off + jit, 0.0)).r;
        base.b = texture(iChannel0, uv - vec2(off - jit, 0.0)).b;
    }
#endif
    vec3 col = base;

    // 1 unit ~ 1 point. The cell height is the most reliable Retina scale.
    float u = iCurrentCursor.w > 1.0 ? iCurrentCursor.w / 20.0 : max(1.0, res.y / 900.0);
    vec2 p = fragCoord / u;
    vec2 size = res / u;
    vec2 cur = (iCurrentCursor.xy + vec2(iCurrentCursor.z, -iCurrentCursor.w) * 0.5) / u;
    vec2 prev = (iPreviousCursor.xy + vec2(iPreviousCursor.z, -iPreviousCursor.w) * 0.5) / u;
#if FLIP_Y
    p.y = size.y - p.y;
    cur.y = size.y - cur.y;
    prev.y = size.y - prev.y;
#endif
    float top = size.y - p.y;      // distance from the top edge
    float cx = size.x * 0.5;
    bool focused = iFocus > 0;
    float sinceFocus = iTime - iTimeFocus;
    float sinceMove = iTime - iTimeCursorChange;
    bool shieldsUp = focused || SHIELDS_UP_UNFOCUSED == 1;
    float charge = focused ? clamp((sinceFocus - 0.15) / 1.1, 0.0, 1.0) : (shieldsUp ? 1.0 : 0.0);
    // Per-pane shield from the shell hook: palette 255 = (level, mode, marker 1).
    bool shellHit = false, shellCharging = false;
#if SHELL_SHIELD
    vec3 sd = iPalette[255];
    if (abs(sd.b * 255.0 - 1.0) < 0.5) {
        charge = min(charge, sd.r);
        if (!focused) charge = sd.r;
        shellHit = sd.g > 0.75;
        shellCharging = sd.g > 0.25 && !shellHit;
    }
#endif
    float cellW = max(iCurrentCursor.z / u, 1.0), cellH = max(iCurrentCursor.w / u, 1.0);

    // Text background = pixels close to the terminal background colour.
    float bgMask = 1.0 - smoothstep(0.03, 0.14, length(base - iBackgroundColor));

#if SHOW_BOKEH
    // Out-of-focus teal lights drifting behind the visor (background only).
    vec2 asp = vec2(res.x / res.y, 1.0);
    vec3 bok = vec3(0.0);
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        vec2 c = vec2(0.5 + 0.42 * sin(iTime * 0.031 * (fi + 1.0) + fi * 1.7),
                      0.5 + 0.38 * cos(iTime * 0.027 * (fi + 2.0) + fi * 2.3));
        float r = 0.16 + 0.06 * hash(fi);
        float g = exp(-pow(length((uv - c) * asp) / r, 2.0));
        float m = mod(fi, 3.0);
        vec3 tint = m < 1.0 ? vec3(0.10, 0.55, 0.62) : (m < 2.0 ? vec3(0.22, 0.58, 0.45) : vec3(0.12, 0.35, 0.75));
        bok += tint * g;
    }
    col += bok * 0.2 * bgMask;
#endif

#if SHOW_TOPO
    {
        // Drifting contour map, like a holo-table terrain scan (background only).
        float n = fbm(p * 0.0055 + vec2(iTime * 0.004, -iTime * 0.003)) * 16.0;
        float f = abs(fract(n) - 0.5);
        float w = max(fwidth(n), 1e-3);
        float iso = smoothstep(0.5 - w * 1.2, 0.5, f);
        float idx = floor(n + 0.5);
        float major = step(mod(idx, 5.0), 0.5);
        vec3 tint = mod(idx, 13.0) == 4.0 ? ROUTE : mix(HUD, vec3(0.2, 0.9, 0.75), 0.4);
        col += tint * iso * (0.05 + 0.07 * major) * bgMask;
    }
#endif

#if SHOW_DUST
    {
        // Sparse hologram particles drifting upward and twinkling.
        vec2 g = p / 24.0 + vec2(0.0, -iTime * 0.12);
        vec2 id = floor(g), fr = fract(g);
        float h = hash2(id);
        vec2 pos = vec2(hash2(id + 3.1), hash2(id + 7.7));
        float tw = 0.5 + 0.5 * sin(iTime * 2.0 + h * 40.0);
        col += mix(HUD, vec3(1.0), 0.3) * step(0.82, h) * smoothstep(0.07, 0.0, length(fr - pos)) * tw * 0.4 * bgMask;
    }
#endif

#if SHOW_GLOW
    vec3 glow = vec3(0.0);
    vec2 px = 1.0 / res;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.785398;
        vec3 s = texture(iChannel0, uv + vec2(cos(ang), sin(ang)) * px * 2.5 * u).rgb;
        glow += max(s - 0.45, 0.0);
    }
    col += glow * 0.09 * (0.6 + 0.4 * HUD);
#endif

#if SHOW_SCANLINES
    col *= 0.965 + 0.035 * sin(fragCoord.y * 3.14159 / (1.5 * u));
#endif

    // Visor vignette with a faint cyan rim.
    vec2 cc = uv - 0.5;
    float v = dot(cc, cc);
    col *= 1.0 - v * 0.6;
    col += HUD * smoothstep(0.2, 0.5, v) * 0.05;

    vec3 hud = vec3(0.0);   // additive HUD layer
    float barHalf = min(230.0, size.x * 0.2);

#if SHOW_FRAME
    {
        // Angled visor frame: top wings off the shield bar, side brackets, bottom plates.
        float d = 1e9;
        for (int s = -1; s <= 1; s += 2) {
            float sx = float(s);
            vec2 t0 = vec2(cx + sx * (barHalf + 14.0), size.y - 22.0);
            vec2 t1 = vec2(cx + sx * (barHalf + 34.0), size.y - 34.0);
            vec2 t2 = vec2(cx + sx * size.x * 0.36, size.y - 34.0);
            vec2 t3 = vec2(cx + sx * size.x * 0.43, size.y - 44.0);
            vec2 t4 = vec2(cx + sx * size.x * 0.5, size.y - 44.0);
            d = min(d, segDist(p, t0, t1));
            d = min(d, segDist(p, t1, t2));
            d = min(d, segDist(p, t2, t3));
            d = min(d, segDist(p, t3, t4));
            // side brackets hugging the edge
            float ex = sx < 0.0 ? 5.0 : size.x - 5.0;
            vec2 s0 = vec2(ex, size.y * 0.66), s1 = vec2(ex - sx * 4.0, size.y * 0.6);
            vec2 s2 = vec2(ex - sx * 4.0, size.y * 0.32), s3 = vec2(ex, size.y * 0.26);
            d = min(d, segDist(p, s0, s1));
            d = min(d, segDist(p, s1, s2));
            d = min(d, segDist(p, s2, s3));
            // bottom centre plate
            d = min(d, segDist(p, vec2(cx + sx * 150.0, 0.0), vec2(cx + sx * 132.0, 20.0)));
            d = min(d, segDist(p, vec2(cx + sx * 132.0, 20.0), vec2(cx, 20.0)));
            // bottom corner wings
            float ox = sx < 0.0 ? 0.0 : size.x;
            vec2 c1 = vec2(cx + sx * size.x * 0.38, 24.0), c2 = vec2(cx + sx * size.x * 0.35, 0.0);
            d = min(d, segDist(p, vec2(ox, 24.0), c1));
            d = min(d, segDist(p, c1, c2));
        }
        hud += HUD * (smoothstep(1.0, 0.2, d) * 0.45 + exp(-d / 4.0) * 0.12);
    }
#endif

#if SHOW_SHIELD
    {
        // Shield bar: an elongated hexagon that drains from both ends.
        vec2 q = vec2(p.x - cx, top - 21.0);
        float h = 7.0;
        float hexd = max(abs(q.y) - h, abs(q.x) + abs(q.y) * 1.3 - barHalf);
        float inside = smoothstep(0.8, -0.8, hexd);
        float outline = smoothstep(1.2, 0.0, abs(hexd + 1.5));
        float lit = step(abs(q.x), charge * barHalf);
        float flicker = 0.85 + 0.15 * hash(floor(q.x / 6.0) + floor(iTime * 9.0));
        bool recharging = (focused && sinceFocus < 1.4) || shellCharging;
        bool critical = charge < 0.2;
        float blink = step(0.5, fract(iTime * 1.5));
        vec3 full = shellHit ? mix(ENEMY, vec3(1.0), 0.25) * (0.8 + 0.2 * flicker)
                  : recharging ? mix(GOLD, HUD, charge) * flicker
                  : critical ? ENEMY * (0.7 + 0.3 * blink)
                  : mix(HUD, vec3(1.0), 0.3);
        vec3 empty = (shieldsUp && !critical && !shellHit) ? HUD * 0.08 : ENEMY * (0.15 + 0.2 * blink);
        // a soft sheen that slides across the bar every few seconds
        float sheen = exp(-pow((q.x - mod(iTime * 160.0, barHalf * 6.0) + barHalf * 3.0) / 30.0, 2.0)) * 0.35;
        vec3 fill = mix(empty, full * (0.75 + sheen), lit) * (0.85 + 0.15 * smoothstep(h, -h, q.y));
        col = mix(col, fill, inside * 0.9);
        hud += ((shieldsUp && !critical && !shellHit) ? HUD : ENEMY) * (outline * 0.7 + exp(-max(hexd, 0.0) / 6.0) * 0.18 * lit);
        // three small cells to the right of the bar
        for (int i = 0; i < 3; i++) {
            vec2 o = vec2(cx + barHalf + 26.0, size.y - 12.0 - float(i) * 6.0);
            vec2 k = p - o;
            hud += HUD * 0.35 * box(k, vec2(0.0, -4.5), vec2(16.0, 0.0))
                 * (1.0 - box(k, vec2(1.0, -3.5), vec2(15.0, -1.0)));
        }
    }
#endif

    int colN = max(0, int((cur.x - 14.0) / cellW));
    int row = max(0, int((size.y - PAD_TOP - cur.y - cellH * 0.5) / cellH));

#if SHOW_TEXT
    {
        float txt = 0.0;
        TEXT(S_SUIT, 25, vec2(28.0, size.y - 10.0), 1.0)
        TEXT(S_SUB, 14, vec2(28.0, size.y - 17.0), 1.0)
        // "ENERGY SHIELD 100%" above the bar
        int pct = int(charge * 100.0 + 0.5);
        int sh[18] = int[](69, 78, 69, 82, 71, 89, 32, 83, 72, 73, 69, 76, 68, 32,
                           pct >= 100 ? 49 : 32, pct >= 10 ? 48 + (pct / 10) % 10 : 32, 48 + pct % 10, 37);
        TEXT(sh, 18, vec2(cx - 36.0, size.y - 5.0), 1.0)
        // Live cursor location, top right: "LOC R012 C045"
        int loc[13] = int[](76, 79, 67, 32, 82, 48 + (row / 100) % 10, 48 + (row / 10) % 10, 48 + row % 10,
                            32, 67, 48 + (colN / 100) % 10, 48 + (colN / 10) % 10, 48 + colN % 10);
        TEXT(loc, 13, vec2(size.x - 28.0 - 13.0 * 4.0, size.y - 10.0), 1.0)
        TEXT(S_VISOR, 20, vec2(cx - 40.0, 12.0), 1.0)
        hud += HUD * txt * 0.55;

        // "Ammo" ticks under the location readout: how far along the line the cursor is.
        float ticks = 30.0;
        vec2 tq = p - vec2(size.x - 28.0 - ticks * 3.0, size.y - 20.0);
        if (tq.x >= 0.0 && tq.x < ticks * 3.0 && tq.y >= -5.0 && tq.y < 0.0) {
            float on = step(floor(tq.x / 3.0), float(colN) / 80.0 * ticks);
            hud += HUD * step(fract(tq.x / 3.0), 0.55) * mix(0.12, 0.6, on);
        }
    }
#endif

#if SHOW_TRACKER
    {
        float R = 56.0;
        vec2 tc = vec2(TRACKER_LEFT == 1 ? R + 18.0 : size.x - R - 18.0, R + 30.0);
        vec2 d = p - tc;
        float r = length(d);
        float ang = atan(d.x, d.y);   // 0 = straight up
        if (r < R) {
            vec3 t = HUD * 0.06;                                         // disc
            t += HUD * 0.10 * step(abs(ang), 0.7) * step(R * 0.3, r);    // field-of-view wedge
            t += HUD * 0.25 * smoothstep(1.2, 0.0, abs(r - R * 0.3));    // inner ring
            t += HUD * 0.12 * smoothstep(1.0, 0.0, abs(r - R * 0.65));
            t += HUD * 0.12 * smoothstep(0.7, 0.0, min(abs(d.x), abs(d.y)));
            float pulse = fract(iTime / 3.0);
            t += HUD * 0.25 * smoothstep(1.5, 0.0, abs(r - pulse * R)) * (1.0 - pulse);
            // player triangle
            vec2 tp = d + vec2(0.0, 2.0);
            t += vec3(0.7) * step(tp.y, 6.0) * step(-2.0, tp.y) * step(abs(tp.x), (6.0 - tp.y) * 0.45);
            // gold blip = your cursor
            vec2 b = (cur / size - 0.5) * 2.0 * R * 0.8;
            t += GOLD * smoothstep(4.5, 1.5, length(d - b));
            col += t;
        }
        hud += HUD * (smoothstep(1.3, 0.0, abs(r - R)) * 0.6 + exp(-abs(r - R) / 6.0) * 0.15);
#if SHOW_RINGS
        {
            // Counter-rotating dashed rings, like the portal rings in the holo-table refs.
            float a = atan(d.y, d.x) / 6.28318;
            float dash = step(0.45, fract((a + iTime * 0.06) * 40.0));
            float arcs = step(0.62, fract((a - iTime * 0.035) * 3.0));
            float ticks = step(0.85, fract((a + iTime * 0.02) * 12.0));
            hud += HUD * smoothstep(0.9, 0.0, abs(r - R - 7.0)) * dash * 0.45;
            hud += HUD * smoothstep(1.2, 0.0, abs(r - R - 13.0)) * arcs * 0.3;
            hud += ROUTE * smoothstep(1.0, 0.0, abs(r - R - 18.0)) * ticks * arcs * 0.5;
        }
#endif
        float txt = 0.0;
        TEXT(S_RANGE, 9, vec2(TRACKER_LEFT == 1 ? tc.x + R + 6.0 : tc.x - R - 42.0, tc.y - R + 10.0), 1.0)
        hud += HUD * txt * 0.45;
    }
#endif

#if SHOW_RETICLE
    // Lock-on reticle that snaps onto the cursor after it jumps.
    if (focused && sinceMove < 0.8 && length(cur - prev) > 1.0) {
        float k = smoothstep(0.0, 0.22, sinceMove);
        float rr = mix(30.0, 15.0, k);
        vec2 d = p - cur;
        float r = length(d);
        float a4 = atan(d.y, d.x) / 1.5708;
        float ring = smoothstep(1.2, 0.0, abs(r - rr)) * step(0.25, abs(fract(a4 + 0.5) - 0.5));
        float ticks = smoothstep(1.0, 0.0, abs(r - rr - 5.0)) * step(abs(fract(a4) - 0.5), 0.18);
        float fade = 1.0 - smoothstep(0.45, 0.8, sinceMove);
        hud += mix(GOLD, HUD, k) * (ring + ticks * 0.7) * fade * 0.9;
    }
#endif

#if SHOW_PLASMA
    if (focused && sinceMove < 0.5 && length(cur - prev) > 1.0) {
        float fade = exp(-sinceMove * 9.0);
        vec2 head = mix(prev, cur, clamp(sinceMove / 0.08, 0.0, 1.0));
        float dl = segDist(p, prev, head);
        float along = clamp(dot(p - prev, cur - prev) / max(dot(cur - prev, cur - prev), 1e-4), 0.0, 1.0);
        float core = exp(-dl / 2.6) * (0.3 + 0.7 * along);
        float haze = exp(-dl / 12.0) * 0.5 * along;
        vec3 plasma = mix(vec3(0.35, 1.0, 0.55), vec3(0.6, 0.95, 1.0), core);
        col += plasma * (core + haze) * fade;
        col += vec3(0.5, 1.0, 0.7) * exp(-length(p - head) / 8.0) * fade;
    }
#endif

#if SHOW_FLARE
    if (focused && sinceFocus < 1.2) {
        float edge = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
        float band = exp(-edge / mix(18.0, 60.0, sinceFocus / 1.2));
        float hex = smoothstep(0.08, 0.0, hexEdge(p / 14.0));
        float fade = 1.0 - sinceFocus / 1.2;
        vec3 fc = mix(GOLD, HUD, smoothstep(0.0, 0.35, sinceFocus));
        col += fc * band * (0.25 + hex * 0.9) * fade * fade;
    }
#endif

    col += hud * (shieldsUp ? 1.0 : 0.6) * (1.0 + band * 0.8);

#if DIM_UNFOCUSED
    if (!focused) {
        float lum = dot(col, vec3(0.299, 0.587, 0.114));
        col = mix(col, vec3(lum) * vec3(0.8, 0.9, 1.0), 0.35) * 0.82;
        col += (hash2(floor(p) + floor(iTime * 12.0)) - 0.5) * 0.035;
    }
#endif

    fragColor = vec4(col, 1.0);
}
