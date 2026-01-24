const String memoryGameShader = '''
// Memory Game — card matching rendered entirely in GLSL
// 6 custom vec4 uniforms pushed from Dart each frame.

uniform vec4 uGame;    // (state, score, lives, countdown)
uniform vec4 uGrid;    // (cols, rows, flipA, flipB)
uniform vec4 uAnim;    // (flipProgress, revealTimer, level, totalCards)
uniform vec4 uStates;  // pk card states (4 per float, 2 bits each)
uniform vec4 uSyms0;   // pk symbol IDs (4 per float, 3 bits each)
uniform vec4 uTouch;   // (touchX, touchY, 0, 0)

// --- SDF helpers ---

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdRoundBox(vec2 p, vec2 b, float r) {
    return sdBox(p, b - r) - r;
}

float sdCircle(vec2 p, float r) {
    return length(p) - r;
}

float sdTriangle(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 e0 = b - a, e1 = c - b, e2 = a - c;
    vec2 v0 = p - a, v1 = p - b, v2 = p - c;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                     vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                     vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// --- Unpack helpers (pure float math, no bitwise ops) ---

float unpack2bit(float pk, float slot) {
    // Extract 2-bit value at position slot (0..3) from pk float
    float shifted = floor(pk / pow(2.0, slot * 2.0));
    return mod(shifted, 4.0);
}

float getCardState(float idx) {
    float pk = 0.0;
    float local = idx;
    if (idx < 4.0) { pk = uStates.x; local = idx; }
    else if (idx < 8.0) { pk = uStates.y; local = idx - 4.0; }
    else if (idx < 12.0) { pk = uStates.z; local = idx - 8.0; }
    else { pk = uStates.w; local = idx - 12.0; }
    return unpack2bit(pk, local);
}

float unpack3bit(float pk, float slot) {
    float shifted = floor(pk / pow(2.0, slot * 3.0));
    return mod(shifted, 8.0);
}

float getSymbol(float idx) {
    float pk = 0.0;
    float local = idx;
    if (idx < 4.0) { pk = uSyms0.x; local = idx; }
    else if (idx < 8.0) { pk = uSyms0.y; local = idx - 4.0; }
    else if (idx < 12.0) { pk = uSyms0.z; local = idx - 8.0; }
    else { pk = uSyms0.w; local = idx - 12.0; }
    return unpack3bit(pk, local);
}

// --- Symbol colors ---

vec3 symColor(float sym) {
    if (sym < 0.5) return vec3(0.9, 0.2, 0.2);
    if (sym < 1.5) return vec3(0.2, 0.5, 0.9);
    if (sym < 2.5) return vec3(0.9, 0.7, 0.1);
    if (sym < 3.5) return vec3(0.8, 0.3, 0.8);
    if (sym < 4.5) return vec3(0.9, 0.6, 0.1);
    if (sym < 5.5) return vec3(0.2, 0.8, 0.3);
    if (sym < 6.5) return vec3(0.9, 0.3, 0.5);
    return vec3(0.3, 0.7, 0.8);
}

// --- Symbol SDFs ---

float drawSymbol(vec2 p, float sym, float sz) {
    if (sym < 0.5) return sdCircle(p, sz * 0.4);
    if (sym < 1.5) return sdBox(p, vec2(sz * 0.35));
    if (sym < 2.5) return sdTriangle(p, vec2(0.0, -sz*0.4), vec2(-sz*0.4, sz*0.3), vec2(sz*0.4, sz*0.3));
    if (sym < 3.5) {
        vec2 rp = abs(p);
        return (rp.x + rp.y) * 0.7071 - sz * 0.4;
    }
    if (sym < 4.5) {
        float a = atan(p.y, p.x);
        float r = length(p);
        return r - sz * 0.4 * (0.6 + 0.4 * cos(a * 5.0));
    }
    if (sym < 5.5) {
        float h = sdBox(p, vec2(sz * 0.4, sz * 0.15));
        float v = sdBox(p, vec2(sz * 0.15, sz * 0.4));
        return min(h, v);
    }
    if (sym < 6.5) {
        vec2 hp = vec2(abs(p.x), -p.y);
        float hb = sdCircle(hp - vec2(sz*0.15, -sz*0.1), sz*0.2);
        float ht = sdTriangle(p, vec2(-sz*0.35, -sz*0.1), vec2(sz*0.35, -sz*0.1), vec2(0.0, sz*0.4));
        return min(hb, ht);
    }
    vec2 hp = abs(p);
    return max(hp.x * 0.866 + hp.y * 0.5, hp.y) - sz * 0.4;
}

// --- 7-segment digit (same as Sky Fairy) ---

float segH(vec2 p, vec2 c, float w, float h) {
    return sdBox(p - c, vec2(w, h));
}

float segV(vec2 p, vec2 c, float w, float h) {
    return sdBox(p - c, vec2(w, h));
}

float digit(vec2 p, int d, float s) {
    float hw = s * 0.35;
    float hh = s * 0.08;
    float vs = s * 0.42;
    float vw = s * 0.08;
    float vh = s * 0.2;

    float top = segH(p, vec2(0.0, vs), hw, hh);
    float mid = segH(p, vec2(0.0, 0.0), hw, hh);
    float bot = segH(p, vec2(0.0, -vs), hw, hh);
    float tl  = segV(p, vec2(-hw, vs*0.5), vw, vh);
    float tr  = segV(p, vec2( hw, vs*0.5), vw, vh);
    float bl  = segV(p, vec2(-hw, -vs*0.5), vw, vh);
    float br  = segV(p, vec2( hw, -vs*0.5), vw, vh);

    float f = 999.0;
    if (d == 0) f = min(min(min(top, bot), min(tl, tr)), min(bl, br));
    if (d == 1) f = min(tr, br);
    if (d == 2) f = min(min(min(top, mid), bot), min(tr, bl));
    if (d == 3) f = min(min(min(top, mid), bot), min(tr, br));
    if (d == 4) f = min(min(mid, tl), min(tr, br));
    if (d == 5) f = min(min(min(top, mid), bot), min(tl, br));
    if (d == 6) f = min(min(min(top, mid), bot), min(min(tl, bl), br));
    if (d == 7) f = min(top, min(tr, br));
    if (d == 8) f = min(min(min(top, mid), bot), min(min(tl, tr), min(bl, br)));
    if (d == 9) f = min(min(min(top, mid), bot), min(min(tl, tr), br));
    return f;
}

// --- Heart shape for lives ---

float sdHeart(vec2 p, float sz) {
    vec2 hp = vec2(abs(p.x), -p.y);
    float hb = sdCircle(hp - vec2(sz*0.3, -sz*0.15), sz*0.35);
    float ht = sdTriangle(p, vec2(-sz*0.65, -sz*0.15), vec2(sz*0.65, -sz*0.15), vec2(0.0, sz*0.7));
    return min(hb, ht);
}

// --- Main ---

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;
    uv.y = 1.0 - uv.y;

    float state = uGame.x;
    float score = uGame.y;
    float lives = uGame.z;
    float countdown = uGame.w;
    float cols = max(uGrid.x, 1.0); // guard div-by-zero
    float rows = max(uGrid.y, 1.0);
    float flipA = uGrid.z;
    float flipB = uGrid.w;
    float flipProgress = uAnim.x;
    float revealTimer = uAnim.y;
    float level = uAnim.z;
    float totalCards = uAnim.w;

    // Background
    vec3 col = mix(vec3(0.08, 0.06, 0.15), vec3(0.12, 0.1, 0.22), uv.y);

    // HUD area at top
    float hudH = 0.1;

    // Grid area
    float gridTop = hudH + 0.02;
    float gridBot = 0.98;
    float gridLeft = 0.05;
    float gridRight = 0.95;

    float gridW = gridRight - gridLeft;
    float gridH = gridBot - gridTop;
    float cellW = gridW / cols;
    float cellH = gridH / rows;
    float cardSize = min(cellW, cellH) * 0.85;

    // Determine which card this fragment is in
    if (uv.y > gridTop && uv.y < gridBot && uv.x > gridLeft && uv.x < gridRight) {
        float gx = (uv.x - gridLeft) / cellW;
        float gy = (uv.y - gridTop) / cellH;
        float cx = floor(gx);
        float cy = floor(gy);
        float cardIdx = cy * cols + cx;

        if (cardIdx < totalCards) {
            // Card center
            vec2 cellCenter = vec2(gridLeft + (cx + 0.5) * cellW,
                                   gridTop + (cy + 0.5) * cellH);
            vec2 lp = uv - cellCenter;
            float halfCard = cardSize * 0.45;

            float cState = getCardState(cardIdx);
            float sym = getSymbol(cardIdx);

            // Handle flip animation
            float scaleX = 1.0;
            float showFace = step(0.5, cState); // 1.0 if cState>=1 (faceUp or matched)

            // During reveal phase, show all
            if (state < 0.5) showFace = 1.0;

            if (abs(cardIdx - flipA) < 0.5 || abs(cardIdx - flipB) < 0.5) {
                if (flipProgress < 0.5) {
                    scaleX = 1.0 - flipProgress * 2.0;
                    showFace = 0.0;
                } else {
                    scaleX = (flipProgress - 0.5) * 2.0;
                    showFace = 1.0;
                }
            }

            vec2 scaledP = vec2(lp.x / max(scaleX, 0.01), lp.y);
            float cardD = sdRoundBox(scaledP, vec2(halfCard / max(scaleX, 0.01), halfCard), halfCard * 0.15);

            float cardAA = smoothstep(0.004, 0.0, cardD);
            if (cardAA > 0.0) {
                vec3 cardCol = vec3(0.2, 0.25, 0.45);
                if (showFace > 0.5) {
                    cardCol = vec3(0.95, 0.93, 0.88);
                    if (cState > 1.5) cardCol = vec3(0.7, 0.95, 0.7); // matched

                    float symD = drawSymbol(scaledP, sym, halfCard * 0.8);
                    float symAA = smoothstep(0.005, 0.0, symD);
                    cardCol = mix(cardCol, symColor(sym), symAA);
                } else {
                    float pat = sin(scaledP.x * 60.0) * sin(scaledP.y * 60.0);
                    cardCol += vec3(0.05) * step(0.0, pat);
                }
                col = mix(col, cardCol, cardAA * max(scaleX, 0.05));
            }
        }
    }

    // === HUD ===

    // Countdown bar
    if (uv.y < hudH * 0.3) {
        float barFill = countdown / 15.0;
        if (uv.x < barFill) {
            vec3 barCol = mix(vec3(0.9, 0.2, 0.2), vec3(0.2, 0.9, 0.3), barFill);
            col = barCol;
        } else {
            col = vec3(0.15);
        }
    }

    // Lives (hearts)
    for (int i = 0; i < 3; i++) {
        if (float(i) < lives) {
            vec2 hPos = vec2(0.06 + float(i) * 0.06, hudH * 0.65);
            float hd = sdHeart(uv - hPos, 0.025);
            float hAA = smoothstep(0.003, 0.0, hd);
            col = mix(col, vec3(0.9, 0.15, 0.2), hAA);
        }
    }

    // Score
    {
        int sc = int(score);
        float dSize = 0.018;
        float sp = dSize * 1.3;
        vec2 sBase = vec2(0.85, hudH * 0.65);
        if (sc < 10) {
            float d0 = digit(uv - sBase, sc, dSize);
            float dAA = smoothstep(0.003, 0.0, d0);
            col = mix(col, vec3(1.0), dAA);
        } else {
            int tens = sc / 10;
            int ones = sc - tens * 10;
            float d0 = digit(uv - sBase + vec2(sp*0.5, 0.0), tens, dSize);
            float d1 = digit(uv - sBase - vec2(sp*0.5, 0.0), ones, dSize);
            float dAA = smoothstep(0.003, 0.0, min(d0, d1));
            col = mix(col, vec3(1.0), dAA);
        }
    }

    // Level indicator
    {
        int lv = int(level);
        vec2 lBase = vec2(0.5, hudH * 0.65);
        float ld = digit(uv - lBase, lv, 0.02);
        float lAA = smoothstep(0.003, 0.0, ld);
        col = mix(col, vec3(0.5, 0.8, 1.0), lAA);
        float lbox = min(sdBox(uv - lBase + vec2(0.04, 0.0), vec2(0.003, 0.012)),
                         sdBox(uv - lBase + vec2(0.035, -0.01), vec2(0.008, 0.003)));
        float lbAA = smoothstep(0.002, 0.0, lbox);
        col = mix(col, vec3(0.5, 0.8, 1.0), lbAA);
    }

    // Reveal phase overlay
    if (state < 0.5) {
        float pulse = sin(iTime * 4.0) * 0.1 + 0.9;
        col *= pulse;
    }

    // Level complete overlay
    if (state > 2.5 && state < 3.5) {
        col = mix(col, vec3(0.2, 0.9, 0.3), 0.2);
    }

    // Game over overlay
    if (state > 3.5) {
        col = mix(col, vec3(0.9, 0.15, 0.1), 0.3);
        float pulse = sin(iTime * 3.0) * 0.15 + 0.85;
        float bob = sin(iTime * 2.0) * 0.015;
        vec2 ac = vec2(0.5, 0.5 + bob);
        float sz = 0.06;
        float arrowD = sdTriangle(uv, ac + vec2(-sz, -sz*0.6),
                                       ac + vec2( sz, -sz*0.6),
                                       ac + vec2(0.0,  sz*0.6));
        float arrowAA = smoothstep(0.004, 0.0, arrowD);
        col = mix(col, vec3(1.0), arrowAA * 0.8 * pulse);
    }

    fragColor = vec4(col, 1.0);
}
''';
