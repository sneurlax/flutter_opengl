const String skyFairyShader = '''
// Sky Fairy — Flappy Bird rendered entirely in GLSL
// Reads 5 custom vec4 uniforms pushed from Dart each frame.

uniform vec4 uGame;  // (state, score, fairyY, fairyVel)
uniform vec4 uRock0; // (x, gapY, gapH, groundScroll)
uniform vec4 uRock1; // (x, gapY, gapH, 0)
uniform vec4 uRock2; // (x, gapY, gapH, 0)
uniform vec4 uRock3; // (x, gapY, gapH, 0)

// --- SDF helpers ---

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
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

float sdCircle(vec2 p, float r) {
    return length(p) - r;
}

float sdRoundBox(vec2 p, vec2 b, float r) {
    return sdBox(p, b - r) - r;
}

// --- 7-segment digit ---

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

    // segments: top, mid, bot (horizontal), tl, tr, bl, br (vertical)
    float top = segH(p, vec2(0.0, vs), hw, hh);
    float mid = segH(p, vec2(0.0, 0.0), hw, hh);
    float bot = segH(p, vec2(0.0, -vs), hw, hh);
    float tl  = segV(p, vec2(-hw, vs*0.5), vw, vh);
    float tr  = segV(p, vec2( hw, vs*0.5), vw, vh);
    float bl  = segV(p, vec2(-hw, -vs*0.5), vw, vh);
    float br  = segV(p, vec2( hw, -vs*0.5), vw, vh);

    float f = 999.0;
    // Encode which segments are on for each digit
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

float drawScore(vec2 uv, float sc) {
    int s = int(sc);
    float digitSize = 0.03;
    float spacing = digitSize * 1.2;
    vec2 base = vec2(0.5, 0.06);

    if (s < 10) {
        return digit(uv - base, s, digitSize);
    }
    // Two digits
    int tens = s / 10;
    int ones = s - tens * 10;
    float d0 = digit(uv - base + vec2(spacing * 0.5, 0.0), tens, digitSize);
    float d1 = digit(uv - base - vec2(spacing * 0.5, 0.0), ones, digitSize);
    return min(d0, d1);
}

// --- Rock rendering ---

float drawRock(vec2 uv, vec4 rock) {
    float rx = rock.x;
    float gy = rock.y;
    float gh = rock.z;
    float rw = 0.05;
    float rr = 0.008;

    // Top rock: from y=0 to gy-gh
    float topH = (gy - gh) * 0.5;
    vec2 topC = vec2(rx + rw, topH);
    float topD = sdRoundBox(uv - topC, vec2(rw, topH + 0.01), rr);

    // Bottom rock: from gy+gh to ground (0.88)
    float botTop = gy + gh;
    float botH = (0.88 - botTop) * 0.5;
    vec2 botC = vec2(rx + rw, botTop + botH);
    float botD = sdRoundBox(uv - botC, vec2(rw, botH + 0.01), rr);

    return min(topD, botD);
}

// Lip (wider cap) at the gap opening
float drawRockLip(vec2 uv, vec4 rock) {
    float rx = rock.x;
    float gy = rock.y;
    float gh = rock.z;
    float rw = 0.05;
    float lipW = 0.012;
    float lipH = 0.015;
    float rr = 0.005;

    // Top lip
    vec2 topLipC = vec2(rx + rw, gy - gh);
    float topLip = sdRoundBox(uv - topLipC, vec2(rw + lipW, lipH), rr);

    // Bottom lip
    vec2 botLipC = vec2(rx + rw, gy + gh);
    float botLip = sdRoundBox(uv - botLipC, vec2(rw + lipW, lipH), rr);

    return min(topLip, botLip);
}

// --- Fairy rendering ---

vec4 drawFairy(vec2 uv, float fy, float fvel) {
    float fx = 0.2;
    float r = 0.03;
    vec2 fc = vec2(fx, fy);

    // Body circle
    float body = sdCircle(uv - fc, r);

    // Wing — small triangle offset
    float wingPhase = sin(iTime * 12.0) * 0.5 + 0.5;
    float wingY = fy - r * 0.4 - wingPhase * r * 0.5;
    vec2 wc = vec2(fx - r * 0.3, wingY);
    float wing = sdCircle(uv - wc, r * 0.55);
    // Cut wing to be only the upper-left part
    wing = max(wing, uv.x - fx + r * 0.1);
    wing = max(wing, uv.y - fy + r * 0.2);

    // Eye
    vec2 eyeC = fc + vec2(r * 0.4, -r * 0.25);
    float eye = sdCircle(uv - eyeC, r * 0.15);

    // Beak
    vec2 beakC = fc + vec2(r * 0.9, r * 0.05);
    float beak = sdBox(uv - beakC, vec2(r * 0.3, r * 0.12));
    // Tilt beak slightly based on velocity
    float tilt = clamp(fvel * 0.8, -0.5, 0.5);

    // Compose fairy color
    vec4 col = vec4(0.0);
    // Wing (lighter yellow, slightly transparent)
    if (wing < 0.002) {
        col = vec4(1.0, 0.95, 0.6, 0.8);
    }
    // Body
    float bodyAA = smoothstep(0.003, 0.0, body);
    if (bodyAA > 0.0) {
        vec3 bodyCol = mix(vec3(1.0, 0.85, 0.1), vec3(0.95, 0.65, 0.05),
                          smoothstep(0.0, r, length(uv - fc + vec2(-r*0.2, -r*0.2))));
        col = vec4(bodyCol, 1.0) * bodyAA + col * (1.0 - bodyAA);
    }
    // Eye (black)
    float eyeAA = smoothstep(0.002, 0.0, eye);
    if (eyeAA > 0.0) col = mix(col, vec4(0.1, 0.1, 0.1, 1.0), eyeAA);
    // Beak (orange)
    float beakAA = smoothstep(0.003, 0.0, beak);
    if (beakAA > 0.0) col = mix(col, vec4(1.0, 0.5, 0.1, 1.0), beakAA);

    return col;
}

// --- Main ---

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;
    // uv.y=0 is top, uv.y=1 is bottom (Linux preamble flips Y)

    float gameState = uGame.x;
    float score = uGame.y;
    float fairyY = uGame.z;
    float fairyVel = uGame.w;
    float groundScroll = uRock0.w;

    // === Sky gradient ===
    vec3 skyTop = vec3(0.4, 0.7, 1.0);
    vec3 skyBot = vec3(0.7, 0.88, 1.0);
    vec3 col = mix(skyTop, skyBot, uv.y);

    // === Clouds (simple procedural) ===
    float cx = fract(uv.x * 2.0 - iTime * 0.01);
    float cloud = smoothstep(0.45, 0.5, cx) * smoothstep(0.55, 0.5, cx);
    cloud *= smoothstep(0.35, 0.25, abs(uv.y - 0.15));
    col = mix(col, vec3(1.0), cloud * 0.3);

    float cx2 = fract(uv.x * 1.5 + 0.3 - iTime * 0.015);
    float cloud2 = smoothstep(0.4, 0.5, cx2) * smoothstep(0.6, 0.5, cx2);
    cloud2 *= smoothstep(0.35, 0.25, abs(uv.y - 0.25));
    col = mix(col, vec3(1.0), cloud2 * 0.2);

    // === Ground ===
    float groundY = 0.88;
    if (uv.y > groundY) {
        // Dirt
        vec3 dirt = vec3(0.55, 0.35, 0.15);
        col = dirt;
        // Grass stripe at top
        float grassH = 0.02;
        if (uv.y < groundY + grassH) {
            float grassPattern = sin((uv.x + groundScroll) * 80.0) * 0.5 + 0.5;
            vec3 grass = mix(vec3(0.2, 0.65, 0.15), vec3(0.3, 0.8, 0.2), grassPattern);
            col = grass;
        }
    }

    // === Rocks ===
    vec4 rockSlots[4];
    rockSlots[0] = uRock0;
    rockSlots[1] = uRock1;
    rockSlots[2] = uRock2;
    rockSlots[3] = uRock3;

    for (int i = 0; i < 4; i++) {
        vec4 rock = rockSlots[i];
        if (rock.x > -0.15 && rock.x < 1.15) {
            float rd = drawRock(uv, rock);
            float lipD = drawRockLip(uv, rock);

            // Lip (darker green)
            float lipAA = smoothstep(0.003, 0.0, lipD);
            if (lipAA > 0.0) {
                col = mix(col, vec3(0.15, 0.5, 0.1), lipAA);
            }
            // Rock body (green)
            float rockAA = smoothstep(0.003, 0.0, rd);
            if (rockAA > 0.0) {
                vec3 rockCol = mix(vec3(0.3, 0.7, 0.2), vec3(0.2, 0.55, 0.15),
                                   smoothstep(rock.x, rock.x + 0.1, uv.x));
                col = mix(col, rockCol, rockAA);
            }
        }
    }

    // === Fairy ===
    vec4 fairyCol = drawFairy(uv, fairyY, fairyVel);
    col = mix(col, fairyCol.rgb, fairyCol.a);

    // === Score ===
    if (gameState > 0.5) {
        float sd = drawScore(uv, score);
        float scoreAA = smoothstep(0.004, 0.0, sd);
        if (scoreAA > 0.0) {
            // White with dark outline
            float outline = smoothstep(0.008, 0.004, sd);
            vec3 scCol = mix(vec3(1.0), vec3(0.15), outline - scoreAA);
            col = mix(col, vec3(1.0), scoreAA);
        }
    }

    // === Menu overlay — pulsing downward arrow ===
    if (gameState < 0.5) {
        float pulse = sin(iTime * 3.0) * 0.15 + 0.85;
        float bob = sin(iTime * 2.0) * 0.015;
        vec2 ac = vec2(0.5, 0.55 + bob);
        float sz = 0.06;
        // Downward-pointing triangle
        float arrowD = sdTriangle(uv, ac + vec2(-sz, -sz*0.6),
                                       ac + vec2( sz, -sz*0.6),
                                       ac + vec2(0.0,  sz*0.6));
        float arrowAA = smoothstep(0.004, 0.0, arrowD);
        col = mix(col, vec3(1.0), arrowAA * 0.9 * pulse);
    }

    // === Death flash ===
    if (gameState > 1.5) {
        // Quick red flash that fades
        // deathTimer is not directly available, but we can use a trick:
        // short flash effect — the fairy's velocity is large positive right after death
        float flash = smoothstep(0.0, 0.4, fairyVel) * 0.3;
        col = mix(col, vec3(1.0, 0.2, 0.1), flash);

        // Pulsing arrow to restart
        if (fairyY >= 0.85) {
            float pulse = sin(iTime * 3.0) * 0.15 + 0.85;
            float bob = sin(iTime * 2.0) * 0.01;
            vec2 ac = vec2(0.5, 0.4 + bob);
            float sz = 0.05;
            float arrowD = sdTriangle(uv, ac + vec2(-sz, -sz*0.6),
                                           ac + vec2( sz, -sz*0.6),
                                           ac + vec2(0.0,  sz*0.6));
            float arrowAA = smoothstep(0.004, 0.0, arrowD);
            col = mix(col, vec3(1.0), arrowAA * 0.7 * pulse);
        }
    }

    fragColor = vec4(col, 1.0);
}
''';
