const String minesweeperShader = '''
// Minesweeper — classic grid rendered entirely in GLSL
// 12 custom vec4 uniforms pushed from Dart each frame.

uniform vec4 uGame;      // (state, timer, flagCount, 0)
uniform vec4 uRow0;
uniform vec4 uRow1;
uniform vec4 uRow2;
uniform vec4 uRow3;
uniform vec4 uRow4;
uniform vec4 uRow5;
uniform vec4 uRow6;
uniform vec4 uRow7;
uniform vec4 uRow8;
uniform vec4 uRow9;
uniform vec4 uHighlight;  // (tapCol, tapRow, deathCol, deathRow)

// --- SDF helpers ---

float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
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

// --- 7-segment digit ---

float segH(vec2 p, vec2 c, float w, float h) { return sdBox(p - c, vec2(w, h)); }

float digit(vec2 p, int d, float s) {
    float hw = s * 0.35, hh = s * 0.08, vs = s * 0.42;
    float vw = s * 0.08, vh = s * 0.2;
    float top = segH(p, vec2(0.0, vs), hw, hh);
    float mid = segH(p, vec2(0.0, 0.0), hw, hh);
    float bot = segH(p, vec2(0.0, -vs), hw, hh);
    float tl  = sdBox(p - vec2(-hw, vs*0.5), vec2(vw, vh));
    float tr  = sdBox(p - vec2( hw, vs*0.5), vec2(vw, vh));
    float bl  = sdBox(p - vec2(-hw, -vs*0.5), vec2(vw, vh));
    float br  = sdBox(p - vec2( hw, -vs*0.5), vec2(vw, vh));
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

// --- Number colors (classic Minesweeper) ---

vec3 numColor(float n) {
    if (n < 1.5) return vec3(0.1, 0.1, 0.9);   // 1 blue
    if (n < 2.5) return vec3(0.0, 0.5, 0.0);   // 2 green
    if (n < 3.5) return vec3(0.9, 0.1, 0.1);   // 3 red
    if (n < 4.5) return vec3(0.1, 0.1, 0.5);   // 4 navy
    if (n < 5.5) return vec3(0.5, 0.1, 0.1);   // 5 maroon
    if (n < 6.5) return vec3(0.0, 0.5, 0.5);   // 6 teal
    if (n < 7.5) return vec3(0.1, 0.1, 0.1);   // 7 black
    if (n < 8.5) return vec3(0.5, 0.5, 0.5);   // 8 gray
    return vec3(0.0);
}

// --- Get row data ---

vec4 getRow(float r) {
    if (r < 0.5) return uRow0;
    if (r < 1.5) return uRow1;
    if (r < 2.5) return uRow2;
    if (r < 3.5) return uRow3;
    if (r < 4.5) return uRow4;
    if (r < 5.5) return uRow5;
    if (r < 6.5) return uRow6;
    if (r < 7.5) return uRow7;
    if (r < 8.5) return uRow8;
    return uRow9;
}

// --- Unpack tile (pure float math, no bitwise ops) ---
// 7-bit encoding: adjCount(4) | hasMine(1)<<4 | state(2)<<5
// Each float packs 3 tiles at 7 bits each (col 9 alone in .w)

float unpack7bit(float pk, float slot) {
    float shifted = floor(pk / pow(2.0, slot * 7.0));
    return mod(shifted, 128.0);
}

// Returns vec3(adjCount, hasMine, tileState)
vec3 decodeTile(float row, float col) {
    vec4 rowData = getRow(row);
    float pk;
    float localIdx;

    if (col < 3.0) { pk = rowData.x; localIdx = col; }
    else if (col < 6.0) { pk = rowData.y; localIdx = col - 3.0; }
    else if (col < 9.0) { pk = rowData.z; localIdx = col - 6.0; }
    else { pk = rowData.w; localIdx = 0.0; }

    float val = unpack7bit(pk, localIdx);

    float adjCount = mod(val, 16.0);
    float hasMine = mod(floor(val / 16.0), 2.0);
    float tileState = mod(floor(val / 32.0), 4.0);

    return vec3(adjCount, hasMine, tileState);
}

// --- Mine SDF ---

float drawMine(vec2 p, float sz) {
    float body = sdCircle(p, sz * 0.35);
    // Axis-aligned spikes
    float h = sdBox(p, vec2(sz * 0.5, sz * 0.08));
    float v = sdBox(p, vec2(sz * 0.08, sz * 0.5));
    // 45-degree rotated spikes
    vec2 rp = vec2(p.x * 0.7071 + p.y * 0.7071, -p.x * 0.7071 + p.y * 0.7071);
    float d1 = sdBox(rp, vec2(sz * 0.45, sz * 0.08));
    float d2 = sdBox(rp, vec2(sz * 0.08, sz * 0.45));
    return min(min(body, min(h, v)), min(d1, d2));
}

// --- Flag SDF ---

float drawFlag(vec2 p, float sz) {
    // Pole
    float pole = sdBox(p - vec2(sz*0.1, 0.0), vec2(sz * 0.04, sz * 0.45));
    // Red triangle flag
    float flag = sdTriangle(p, vec2(sz*0.1, -sz*0.4),
                                vec2(sz*0.1, -sz*0.05),
                                vec2(-sz*0.35, -sz*0.22));
    return min(pole, flag);
}

// --- Main ---

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;
    uv.y = 1.0 - uv.y;

    float gameState = uGame.x;
    float timer = uGame.y;
    float flagCount = uGame.z;
    float tapCol = uHighlight.x;
    float tapRow = uHighlight.y;
    float deathCol = uHighlight.z;
    float deathRow = uHighlight.w;

    // Background
    vec3 col = vec3(0.6, 0.6, 0.6);

    // HUD area at top
    float hudH = 0.08;

    // Grid layout: 10x10
    float gridTop = hudH + 0.01;
    float gridBot = 0.99;
    float gridLeft = 0.005;
    float gridRight = 0.995;
    float cellSize = min((gridRight - gridLeft) / 10.0, (gridBot - gridTop) / 10.0);

    // Center the grid
    float totalW = cellSize * 10.0;
    float totalH = cellSize * 10.0;
    float gx0 = (1.0 - totalW) * 0.5;
    float gy0 = gridTop + ((gridBot - gridTop) - totalH) * 0.5;

    // Determine cell
    float relX = (uv.x - gx0) / cellSize;
    float relY = (uv.y - gy0) / cellSize;
    float cellCol = floor(relX);
    float cellRow = floor(relY);

    if (relX >= 0.0 && relX < 10.0 && relY >= 0.0 && relY < 10.0 &&
        cellCol >= 0.0 && cellCol < 10.0 && cellRow >= 0.0 && cellRow < 10.0) {

        vec2 cellCenter = vec2(gx0 + (cellCol + 0.5) * cellSize,
                               gy0 + (cellRow + 0.5) * cellSize);
        vec2 lp = uv - cellCenter;
        float halfCell = cellSize * 0.48;

        vec3 tile = decodeTile(cellRow, cellCol);
        float adjCount = tile.x;
        float hasMine = tile.y;
        float tileState = tile.z;

        // Cell border
        float border = sdBox(lp, vec2(halfCell));
        float borderAA = smoothstep(0.002, 0.0, abs(border) - 0.001);

        float showRevealed = 0.0;
        if (abs(tileState - 1.0) < 0.5) showRevealed = 1.0;
        // On loss, reveal all mines
        if (gameState > 2.5 && hasMine > 0.5) showRevealed = 1.0;

        if (showRevealed > 0.5) {
            // Revealed tile: flat light gray
            float tileD = sdBox(lp, vec2(halfCell - 0.002));
            float tileAA = smoothstep(0.002, 0.0, tileD);

            vec3 tileCol = vec3(0.78, 0.78, 0.78);

            if (hasMine > 0.5) {
                // Mine
                if (abs(cellCol - deathCol) < 0.5 && abs(cellRow - deathRow) < 0.5) {
                    tileCol = vec3(0.9, 0.2, 0.2); // red background for death mine
                }
                float mineD = drawMine(lp, halfCell * 0.7);
                float mineAA = smoothstep(0.003, 0.0, mineD);
                tileCol = mix(tileCol, vec3(0.1), mineAA);
            } else if (adjCount > 0.5) {
                // Number
                float numD = digit(lp, int(adjCount), halfCell * 0.6);
                float numAA = smoothstep(0.003, 0.0, numD);
                tileCol = mix(tileCol, numColor(adjCount), numAA);
            }

            col = mix(col, tileCol, tileAA);
        } else {
            // Hidden tile: 3D beveled button
            float tileD = sdBox(lp, vec2(halfCell - 0.002));
            float tileAA = smoothstep(0.002, 0.0, tileD);

            vec3 tileCol = vec3(0.75, 0.75, 0.75);

            // Bevel: lighter top-left, darker bottom-right
            float bevelW = halfCell * 0.12;
            // Top edge (lighter)
            if (lp.y < -halfCell + bevelW && abs(lp.x) < halfCell) {
                tileCol = vec3(0.92, 0.92, 0.92);
            }
            // Left edge (lighter)
            if (lp.x < -halfCell + bevelW && abs(lp.y) < halfCell) {
                tileCol = vec3(0.88, 0.88, 0.88);
            }
            // Bottom edge (darker)
            if (lp.y > halfCell - bevelW && abs(lp.x) < halfCell) {
                tileCol = vec3(0.55, 0.55, 0.55);
            }
            // Right edge (darker)
            if (lp.x > halfCell - bevelW && abs(lp.y) < halfCell) {
                tileCol = vec3(0.58, 0.58, 0.58);
            }

            // Flag
            if (tileState > 1.5) {
                float flagD = drawFlag(lp, halfCell * 0.7);
                float flagAA = smoothstep(0.003, 0.0, flagD);
                // Red flag, dark pole
                vec3 flagCol = vec3(0.9, 0.15, 0.15);
                float poleD = sdBox(lp - vec2(halfCell*0.7*0.1, 0.0),
                                    vec2(halfCell*0.7*0.04, halfCell*0.7*0.45));
                float poleAA = smoothstep(0.002, 0.0, poleD);
                tileCol = mix(tileCol, vec3(0.2), poleAA);
                tileCol = mix(tileCol, flagCol, flagAA);
            }

            // Highlight last tap
            if (abs(cellCol - tapCol) < 0.5 && abs(cellRow - tapRow) < 0.5 && gameState < 1.5) {
                tileCol *= 1.1;
            }

            col = mix(col, tileCol, tileAA);
        }

        // Grid lines
        col = mix(col, vec3(0.5), borderAA * 0.3);
    }

    // === HUD ===
    if (uv.y < hudH) {
        col = vec3(0.75, 0.75, 0.75);

        // Timer
        {
            int t = int(timer);
            int mins = t / 60;
            int secs = t - mins * 60;
            float dSz = 0.015;
            float sp = dSz * 1.2;
            vec2 tBase = vec2(0.5, hudH * 0.5);

            // Minutes digit
            float d0 = digit(uv - tBase + vec2(sp * 1.5, 0.0), mins, dSz);
            // Colon (two dots)
            float colon = min(sdCircle(uv - tBase + vec2(sp * 0.5, dSz * 0.2), 0.003),
                              sdCircle(uv - tBase + vec2(sp * 0.5, -dSz * 0.2), 0.003));
            // Tens of seconds
            float d1 = digit(uv - tBase - vec2(sp * 0.2, 0.0), secs / 10, dSz);
            // Ones of seconds
            float d2 = digit(uv - tBase - vec2(sp * 1.3, 0.0), secs - (secs/10)*10, dSz);

            float tAA = smoothstep(0.002, 0.0, min(min(d0, min(d1, d2)), colon));
            col = mix(col, vec3(0.1), tAA);
        }

        // Flag counter
        {
            int fc = int(flagCount);
            float dSz = 0.015;
            vec2 fBase = vec2(0.12, hudH * 0.5);
            // Small flag icon
            float fi = drawFlag(uv - fBase + vec2(0.04, 0.0), 0.02);
            float fiAA = smoothstep(0.002, 0.0, fi);
            col = mix(col, vec3(0.9, 0.15, 0.15), fiAA);
            // Number
            if (fc < 10) {
                float d0 = digit(uv - fBase, fc, dSz);
                float dAA = smoothstep(0.002, 0.0, d0);
                col = mix(col, vec3(0.9, 0.1, 0.1), dAA);
            } else {
                float d0 = digit(uv - fBase + vec2(dSz*0.7, 0.0), fc / 10, dSz);
                float d1 = digit(uv - fBase - vec2(dSz*0.7, 0.0), fc - (fc/10)*10, dSz);
                float dAA = smoothstep(0.002, 0.0, min(d0, d1));
                col = mix(col, vec3(0.9, 0.1, 0.1), dAA);
            }
        }
    }

    // Win overlay
    if (gameState > 1.5 && gameState < 2.5) {
        col = mix(col, vec3(0.2, 0.9, 0.3), 0.2);
    }

    // Loss overlay
    if (gameState > 2.5) {
        col = mix(col, vec3(0.9, 0.15, 0.1), 0.15);
    }

    fragColor = vec4(col, 1.0);
}
''';
