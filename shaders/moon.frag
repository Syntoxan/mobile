#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;

out vec4 fragColor;

// ───────────── tunables ─────────────
const float R_MOON = 0.40;   // disc radius in uv units (diameter = 40% of canvas)
const float EL     = 0.30;   // sun elevation above the lunar equator (rad)

// ───────────── hash / noise ─────────────
float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // quintic fade
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {                       // 2 octaves, 0..1
  float s = 0.5 * vnoise(p);
  p = mat2(0.8, -0.6, 0.6, 0.8) * p * 2.03 + 11.7;
  return (s + 0.25 * vnoise(p)) * 1.3333;
}

float fbm4(vec2 p) {                       // 4 octaves, 0..1
  mat2 rot = mat2(0.8, -0.6, 0.6, 0.8);
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    s += a * vnoise(p);
    p = rot * p * 2.03 + 11.7;
    a *= 0.5;
  }
  return s * 1.0667;
}

// ───────────── Voronoi crater layer ─────────────
// returns: xy = surface slope (east,north), z = albedo modulation, w = cavity
vec4 craterLayer(vec2 g) {
  vec2 ic = floor(g);
  float f1 = 9.0;
  float f2 = 9.0;
  float id = 0.0;
  vec2 bv = vec2(0.0);
  for (int j = -1; j < 2; j++) {
    for (int k = -1; k < 2; k++) {
      vec2 c = ic + vec2(float(k), float(j));
      float h = hash21(c);
      vec2 q = c + 0.5 + 0.4 * vec2(sin(h * 6.2832), cos(h * 5.0));
      vec2 dv = g - q;
      float d = length(dv);
      if (d < f1) { f2 = f1; f1 = d; id = h; bv = dv; }
      else if (d < f2) { f2 = d; }
    }
  }
  float rad = mix(0.16, 0.44, fract(id * 7.13 + 0.31));
  float d   = f1 / rad;
  float e   = smoothstep(0.0, 1.0, (f2 - f1) * 12.0);      // cell edge (hides seams)
  float b   = max(1.0 - d * d, 0.0);                       // parabolic bowl
  float u   = (d - 1.0) / 0.16;
  float rim = exp(-u * u);                                 // gaussian rim ridge
  float slope = 0.90 * d * b - 0.88 * u * rim;             // analytic d(height)/d(d)
  vec2 dir  = bv / max(f1, 1e-3);
  vec2 grad = dir * slope * e;

  float infl   = 1.0 - smoothstep(0.85, 1.9, d);
  float cellB  = 0.5 + 0.5 * sin(id * 6.2832 + 1.3);       // per-cell brightness
  float fresh  = step(0.84, fract(id * 13.7 + 0.11));      // young bright craters
  float ej     = exp(-max(d - 1.0, 0.0) * 2.4) * (1.0 - smoothstep(1.0, 2.7, d));
  float bright = (cellB - 0.5) * 0.30 * infl + fresh * (0.40 * ej + 0.14 * b);
  bright *= 0.3 + 0.7 * e;
  return vec4(grad, bright, b * e);
}

// Tycho-style bright ray system (periodic spokes around a crater)
float rays(vec2 tc, vec2 c, float seed, float reach) {
  vec2 d = tc - c;
  float r = length(d);
  float a = (atan(d.y, d.x + 1e-5) / 6.2832 + 0.5) * 19.0 + seed;
  float i = floor(a);
  float f = fract(a);
  f = f * f * (3.0 - 2.0 * f);
  float n = mix(hash21(vec2(mod(i, 19.0), seed)),
                hash21(vec2(mod(i + 1.0, 19.0), seed)), f);
  float spokes = smoothstep(0.50, 0.92, n);
  return spokes * exp(-r * r / (reach * reach)) * smoothstep(0.03, 0.12, r);
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  vec2 uv = (pos / uSize - 0.5) * 2.0;
  uv *= uSize / min(uSize.x, uSize.y);     // square pixels, short side = -1..1
  uv.y = -uv.y;                            // y up
  float r = length(uv);

  if (r > 0.975) {                         // fully transparent outside the glow
    fragColor = vec4(0.0);
    return;
  }

  float t  = uTime;
  float px = 2.0 / min(uSize.x, uSize.y);
  float aa = 0.35 * px;

  // ── slow phase sweep (waxing gibbous → near quarter) + calm breathing
  float la = 0.92 + 0.36 * sin(t * 0.12);
  vec3  L  = normalize(vec3(sin(la) * cos(EL), sin(EL), cos(la) * cos(EL)));
  float phaseAng = acos(clamp(L.z, -1.0, 1.0));
  float illum    = 0.5 + 0.5 * L.z;
  float breath   = 1.0 + 0.055 * sin(t * 0.9) + 0.025 * sin(t * 0.37 + 1.7);

  // ── drifting thin cloud / haze (domain-warped fbm)
  vec2 cp = uv * 1.5 + vec2(t * 0.030, -t * 0.011);
  vec2 cw = vec2(fbm2(cp * 0.8 + vec2(t * 0.012, 3.1)),
                 fbm2(cp * 0.8 + vec2(7.4, -t * 0.009)));
  float hz = smoothstep(0.40, 0.76, fbm2(cp + 1.6 * cw));

  // ── glow: Moffat PSF (long optical tails) + broad scatter, smooth fade to 0
  float x    = max(r - R_MOON, 0.0);
  float moff = pow(1.0 + x * x / 0.0081, -1.6);
  float gI   = 0.40 * moff + 0.17 * exp(-x * 3.6);
  vec2  dirP = uv / max(r, 1e-4);
  float litSide = 0.80 + 0.20 * dot(dirP, normalize(L.xy));
  float fade = 1.0 - smoothstep(0.58, 0.97, r);
  gI *= fade * (0.58 + 0.42 * illum) * litSide * breath * (0.82 + 0.40 * hz);
  vec3 gCol = mix(vec3(1.0, 0.96, 0.88), vec3(0.42, 0.60, 1.0), smoothstep(0.0, 0.32, x));

  // ── 22° ice-crystal halo ring (reddish inside, blue outside, patchy)
  float ang = atan(uv.y, uv.x + 1e-5) / 6.2832 + 0.5;
  float ra  = ang * 9.0 + t * 0.05;
  float ri  = floor(ra);
  float rf  = fract(ra);
  rf = rf * rf * (3.0 - 2.0 * rf);
  float rn  = mix(hash21(vec2(mod(ri, 9.0), 4.2)),
                  hash21(vec2(mod(ri + 1.0, 9.0), 4.2)), rf);
  float ringW = (r - 0.74) / 0.05;
  float ring  = exp(-ringW * ringW) * (0.30 + 0.70 * rn) * (0.35 + 0.65 * hz);
  ring *= (1.0 - smoothstep(0.88, 0.97, r)) * (0.5 + 0.5 * illum) * 0.20 * breath;
  vec3 ringCol = mix(vec3(1.0, 0.70, 0.50), vec3(0.50, 0.68, 1.0), smoothstep(0.69, 0.80, r));

  vec3 glow = gCol * gI + ringCol * ring;

  // ── a few twinkling stars (own cell only, no loop)
  vec2  sg = uv * 5.5;
  vec2  sc = floor(sg);
  float sh = hash21(sc + 3.7);
  vec2  sj = (vec2(hash21(sc + 1.3), hash21(sc + 8.1)) - 0.5) * 0.34;
  vec2  sd = sg - (sc + 0.5 + sj);
  float tw = 0.55 + 0.45 * sin(t * (0.9 + 1.7 * sh) + sh * 40.0);
  float star = step(0.88, sh) * exp(-dot(sd, sd) * 45.0) * tw;
  float sMask = smoothstep(R_MOON + 0.10, R_MOON + 0.26, r) * (1.0 - smoothstep(0.80, 0.94, r));
  star *= sMask * (1.0 - clamp(gI * 2.4, 0.0, 1.0)) * (1.0 - 0.8 * hz);
  glow += vec3(0.80, 0.88, 1.0) * star * 0.85;

  // ── the moon itself
  vec3 surf = vec3(0.0);
  if (r < R_MOON + aa) {
    vec2  nn = uv / R_MOON;
    float z  = sqrt(max(1.0 - dot(nn, nn), 0.0));
    vec3  N  = vec3(nn, z);

    // libration: tiny rocking of the globe (rotate into body frame)
    float ay = 0.17 * sin(t * 0.16 + 0.7);
    float ax = 0.11 * sin(t * 0.11);
    float cy = cos(ay); float sy = sin(ay);
    float cx = cos(ax); float sx = sin(ax);
    vec3 B = vec3(cy * N.x + sy * N.z, N.y, -sy * N.x + cy * N.z);
    B = vec3(B.x, cx * B.y - sx * B.z, sx * B.y + cx * B.z);

    // sinusoidal (equal-area) map: craters foreshorten correctly toward the limb
    float lat = asin(clamp(B.y, -1.0, 1.0));
    float lon = atan(B.x, B.z + 1e-5);
    vec2  tc  = vec2(lon * cos(lat), lat);

    // maria: domain-warped fbm, biased toward the north-west like the real Moon
    vec2  s  = tc * 1.25;
    vec2  w  = vec2(fbm2(s + vec2(1.7, 9.2)), fbm2(s + vec2(8.3, 2.8)));
    float mm = fbm4(s * 1.15 + 2.0 * w);
    mm += 0.07 * tc.y - 0.03 * tc.x + 0.06 * (vnoise(tc * 14.0) - 0.5);
    float maria = smoothstep(0.55, 0.62, mm);

    // craters: two Voronoi scales, damped near the limb and inside maria
    float lf1 = smoothstep(0.03, 0.26, z);
    float lf2 = smoothstep(0.12, 0.45, z);
    vec4 c1 = craterLayer(tc * 2.1 + vec2(3.7, 1.9));
    vec4 c2 = craterLayer(tc * 5.7 + vec2(9.1, 4.3));
    float cm = 1.0 - 0.6 * maria;
    c1 = vec4(c1.xy * cm, c1.z, c1.w * cm);
    c1 *= lf1;
    c2 *= lf2;

    // bump-mapped normal from analytic crater slopes
    vec2 gs = c1.xy * 1.35 + c2.xy * 0.75;
    vec3 T  = normalize(vec3(N.z + 1e-3, 0.0, -N.x));
    vec3 U  = cross(N, T);
    vec3 Np = normalize(N - (gs.x * T + gs.y * U));

    // ray systems (Tycho, Copernicus) + regolith mottling + mineral tint
    float rayAmt = rays(tc, vec2(-0.14, -0.75), 1.7, 0.85)
                 + 0.55 * rays(tc, vec2(-0.34, 0.17), 5.3, 0.45);
    float mottle = fbm2(tc * 8.5 + 4.0);
    float tn = fbm2(tc * 2.0 + vec2(9.0, 3.0));
    vec3 tint = mix(vec3(1.06, 0.98, 0.90), vec3(0.90, 1.00, 1.12), smoothstep(0.35, 0.65, tn));

    vec3 alb = mix(vec3(0.95, 0.92, 0.85), vec3(0.33, 0.36, 0.43), maria);
    alb *= mix(vec3(1.0), tint, maria);
    alb *= 0.86 + 0.28 * mix(0.5, mottle, lf2);
    alb *= 1.0 + c1.z + c2.z;
    alb += vec3(0.34, 0.33, 0.30) * clamp(rayAmt, 0.0, 1.0) * lf1;
    alb *= 1.0 - 0.22 * c1.w - 0.10 * c2.w;

    // Lunar-Lambert / Lommel–Seeliger photometry (flat, "moon-like" disc)
    float mu   = z;
    float mu0  = dot(Np, L);
    float mu0s = dot(N, L);
    float m0   = clamp((mu0 + 0.07) / 1.07, 0.0, 1.0);          // rough-surface wrap
    float ls   = min(2.0 * m0 / (m0 + mu + 0.03), 1.10);
    float lw   = exp(-phaseAng * 1.1);
    float day  = smoothstep(-0.10, 0.14, mu0s);                  // soft terminator
    float refl = (lw * ls + (1.0 - lw) * m0) * day;

    // earthshine on the night side
    vec3 es = alb * vec3(0.50, 0.68, 1.0) * (0.040 + 0.030 * (1.0 - illum)) * (0.45 + 0.55 * mu);

    vec3 col = alb * refl * 1.35 + es;
    col *= 0.86 + 0.14 * sqrt(z);                                // gentle roundness
    col = 1.0 - exp(-col * 1.9);                                 // soft filmic roll-off
    col = mix(col, vec3(0.78, 0.87, 1.0) * 0.85, hz * 0.26);     // haze veil
    surf = col;
  }

  // ── composite, PREMULTIPLIED alpha
  float cov = 1.0 - smoothstep(R_MOON - aa, R_MOON + aa, r);
  vec3  rgb = surf * cov + glow * (1.0 - cov);
  float a   = cov + max(max(glow.r, glow.g), glow.b) * (1.0 - cov);

  float dn = (hash21(pos) - 0.5) * (1.5 / 255.0) * fade;        // anti-banding dither
  rgb = max(rgb + dn, 0.0);
  a   = clamp(max(a + dn, max(max(rgb.r, rgb.g), rgb.b)), 0.0, 1.0);
  fragColor = vec4(rgb, a);
}
