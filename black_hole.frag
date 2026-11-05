#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uDark;

out vec4 fragColor;

// ===== named constants =====
const float TAU = 6.28318530718;
const float PI = 3.14159265359;
const float LOOP_T = 16.0;          // seamless loop length (s)
const float DARK_BOOST = 0.6;       // 0..1, strength of dark-mode extras

const int MAX_STEPS = 96;           // RK4 steps (max)
const float H0 = 0.11;              // base step in phi
const float H_U = 2.5;              // step shrink near the hole
const float U_CAP = 0.5;            // u = 1/r above this = captured
const float M_SCALE = 0.04811;      // screen units per M (void radius 0.25 / 5.196)
const float SIN_I = 0.9781;         // inclination 78 deg
const float COS_I = 0.2079;
const float R_IN = 3.3;             // disk inner radius (M)
const float R_OUT = 20.0;           // disk outer radius (M)
const float RHO_IN = 0.165;         // R_IN / R_OUT
const float DSDRHO = 9.5;           // band index change per rho unit (AA width)
const float G_EXP = 0.28;           // how strongly g shifts band colour
const float DOPPLER_K = 0.10;       // flat-disk doppler tilt

const vec2 VOID_C = vec2(0.010, -0.020);
const float RING_R = 0.262;         // photon ring radius
const float RING_W = 0.004;         // photon ring half thickness
const float GLOW_R0 = 0.272;        // lensed glow starts here (black gap before it)
const float GLOW_R1 = 0.585;        // lensed glow window end

const vec2 DISK_C = vec2(0.035, -0.045);
const vec2 TILT = vec2(0.94996, 0.31234);   // cos/sin of 18.2 deg
const float DISK_A = 0.965;
const float DISK_B = 0.2006;                // A * cos(i)

const vec3 C0 = vec3(0.012, 0.024, 0.059);  // #03060F
const vec3 C1 = vec3(0.043, 0.086, 0.275);  // #0B1646
const vec3 C2 = vec3(0.086, 0.161, 0.420);  // #16296B
const vec3 C3 = vec3(0.169, 0.298, 0.620);  // #2B4C9E
const vec3 C4 = vec3(0.435, 0.639, 0.933);  // #6FA3EE
const vec3 C5 = vec3(0.784, 0.886, 1.000);  // #C8E2FF
const vec3 C6 = vec3(1.0);                  // #FFFFFF
const vec3 LIFT = vec3(0.078, 0.137, 0.373); // #14235F dark-mode floor

// periodic hash
float hash11(float x) { return fract(sin(x * 127.1 + 311.7) * 43758.5453); }

// periodic value noise (period per, integer-valued)
float vnoise(float x, float per, float seed) {
  float i = floor(x);
  float f = x - i;
  f = f * f * (3.0 - 2.0 * f);
  float a = hash11(mod(i, per) + seed);
  float b = hash11(mod(i + 1.0, per) + seed);
  return mix(a, b, f);
}

// analytic coverage from signed distance and pixel size
float cov(float d, float px) { return clamp(0.5 - d / px, 0.0, 1.0); }

// premultiplied over
vec4 over(vec4 dst, vec3 col, float a) {
  return vec4(col * a + dst.rgb * (1.0 - a), a + dst.a * (1.0 - a));
}

vec2 rot2(vec2 v, float a) {
  float c = cos(a);
  float s = sin(a);
  return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

vec2 rotCS(vec2 v, vec2 cs) {
  return vec2(cs.x * v.x - cs.y * v.y, cs.y * v.x + cs.x * v.y);
}

float sdEll(vec2 l, vec2 ab) { return (length(l / ab) - 1.0) * min(ab.x, ab.y); }

float smin(float a, float b, float k) {
  float h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

// dark-mode lift: black -> #14235F, white stays white
vec3 theme(vec3 c, float dk) { return mix(c, c * (1.0 - LIFT) + LIFT, dk); }

// flat posterised band palette, k = 0..7 (centre -> rim)
vec3 palBand(float k) {
  vec3 c = C6;
  c = mix(c, C5, step(0.5, k));
  c = mix(c, C4, step(1.5, k));
  c = mix(c, C3, step(2.5, k));
  c = mix(c, C2, step(3.5, k));
  c = mix(c, C1, step(4.5, k));
  c = mix(c, vec3(0.060, 0.115, 0.340), step(5.5, k));
  c = mix(c, C0, step(6.5, k));
  return c;
}

// light streaks flowing along bands: two-phase cross-fade keeps the loop seamless
float streakField(float ang, float k, float t) {
  float u0 = fract(t / LOOP_T);
  float w0 = 1.0 - abs(2.0 * u0 - 1.0);
  float u1 = fract(t / LOOP_T + 0.5);
  float sp = 4.0 + 1.5 * k;
  float x = ang / TAU * 18.0 + k * 5.3;
  float n0 = vnoise(x - sp * u0, 18.0, k * 19.0);
  float n1 = vnoise(x - sp * u1, 18.0, k * 19.0);
  return smoothstep(0.60, 0.92, mix(n1, n0, w0));
}

// colour of the disk at normalised radius rho (also used for lensed images)
vec3 bandColor(float rho, float ang, float ws, float t) {
  float s = pow(clamp((rho - RHO_IN) / (1.0 - RHO_IN), 0.0, 1.0), 0.85) * 8.0;
  float fl = floor(s);
  float k = min(fl, 7.0);
  float f = s - fl;
  vec3 c = mix(palBand(k), palBand(min(k + 1.0, 7.0)), smoothstep(1.0 - ws, 1.0, f));
  float st = streakField(ang, k, t);
  c = mix(c, palBand(max(k - 1.0, 0.0)), 0.7 * st * step(0.5, k));
  float ei = floor(s + 0.5);
  float ed = min(f, 1.0 - f);
  float odd = step(0.5, mod(ei, 2.0)) * step(0.5, ei) * step(ei, 7.5);
  float lineA = (1.0 - smoothstep(0.7 * ws, 1.5 * ws, ed)) * odd;
  return mix(c, C4, 0.85 * lineA);
}

// cubic Hermite interpolation of u inside one step
float herm(float u0, float w0, float u1, float w1, float h, float s) {
  float s2 = s * s;
  float s3 = s2 * s;
  return (2.0 * s3 - 3.0 * s2 + 1.0) * u0 + (s3 - 2.0 * s2 + s) * h * w0
       + (-2.0 * s3 + 3.0 * s2) * u1 + (s3 - s2) * h * w1;
}

// Schwarzschild null geodesic u'' = -u + 3u^2 (M=1), RK4 with adaptive step.
// Returns radii of the 1st and 2nd disk-plane crossings (0 = none).
vec2 traceDisk(float b, float phi1, float phi2, bool need2) {
  float u = 0.0;
  float w = 1.0 / b;
  float ph = 0.0;
  float r1 = 0.0;
  float r2 = 0.0;
  float phEnd = need2 ? phi2 : phi1;
  for (int i = 0; i < MAX_STEPS; i++) {
    float h = H0 / (1.0 + H_U * u);
    float k1w = u * (3.0 * u - 1.0);
    float u2 = u + 0.5 * h * w;
    float w2 = w + 0.5 * h * k1w;
    float k2w = u2 * (3.0 * u2 - 1.0);
    float u3 = u + 0.5 * h * w2;
    float w3 = w + 0.5 * h * k2w;
    float k3w = u3 * (3.0 * u3 - 1.0);
    float u4 = u + h * w3;
    float w4 = w + h * k3w;
    float k4w = u4 * (3.0 * u4 - 1.0);
    float un = u + h / 6.0 * (w + 2.0 * w2 + 2.0 * w3 + w4);
    float wn = w + h / 6.0 * (k1w + 2.0 * k2w + 2.0 * k3w + k4w);
    float pn = ph + h;
    if (r1 == 0.0 && pn >= phi1) {
      float s = clamp((phi1 - ph) / h, 0.0, 1.0);
      r1 = 1.0 / max(herm(u, w, un, wn, h, s), 1e-4);
    }
    if (need2 && r2 == 0.0 && pn >= phi2) {
      float s = clamp((phi2 - ph) / h, 0.0, 1.0);
      r2 = 1.0 / max(herm(u, w, un, wn, h, s), 1e-4);
    }
    u = un;
    w = wn;
    ph = pn;
    if (u > U_CAP || u < 0.0 || ph >= phEnd) break;
  }
  return vec2(r1, r2);
}

// lensed image of the disk (top ring = primary, arc under the void = secondary)
vec4 glowPix(vec2 p, float px, float t) {
  vec2 v = p - VOID_C;
  float rr = length(v);
  if (rr < GLOW_R0 - 2.0 * px || rr > GLOW_R1) return vec4(0.0);
  float win = smoothstep(GLOW_R0 - px, GLOW_R0 + px, rr)
            * (1.0 - smoothstep(GLOW_R1 - 0.05, GLOW_R1, rr));
  vec2 q = rotCS(v, vec2(TILT.x, -TILT.y));
  float al = atan(q.y, q.x);
  float ph = TAU * t / LOOP_T;
  float b = rr / M_SCALE;
  b *= 1.0 + 0.010 * sin(ph) + 0.012 * sin(3.0 * al + ph) + 0.006 * sin(5.0 * al - 2.0 * ph);
  float sa = sin(al);
  float phi1 = atan(COS_I, -sa * SIN_I);
  vec2 rs = traceDisk(b, phi1, phi1 + PI, sa < 0.0);
  float r = rs.x;
  if (r < R_IN * 0.9 || r > R_OUT * 1.05) r = rs.y;
  if (r < R_IN * 0.9 || r > R_OUT * 1.05) return vec4(0.0);
  float om = inversesqrt(r * r * r);
  float gt = sqrt(max(1.0 - 3.0 / r, 0.02));
  float g = gt / max(1.0 + om * b * SIN_I * cos(al), 0.3);
  float rho = r / R_OUT;
  float rc = rho * clamp(pow(g, -G_EXP), 0.75, 1.35);
  float ws = clamp(px * 28.0, 0.03, 0.45);
  vec3 col = bandColor(rc, al, ws, t);
  float aEnd = 1.0 - smoothstep(1.0 - ws / DSDRHO, 1.0 + ws / DSDRHO, rho);
  float aSt = smoothstep(R_IN * 0.88, R_IN * 0.98, r);
  return vec4(col, win * aEnd * aSt);
}

// pointed lens silhouette of the disk (signed distance, approximate)
float lensSD(vec2 p) {
  vec2 q = rotCS(p - DISK_C, vec2(TILT.x, -TILT.y));
  float X = q.x / 0.985;
  float m = max(1.0 - X * X, 0.003);
  float h = 0.218 * m * sqrt(m);
  float rho = abs(q.y) / h;
  float gy = 1.0 / h;
  float gx = rho * 3.0 * abs(X) / (0.985 * m);
  float core = clamp((rho - 1.0) / max(sqrt(gy * gy + gx * gx), 1.0), -0.4, 0.4);
  float tip = length(vec2(abs(q.x) - 0.985, q.y));
  return mix(core, tip, step(0.985, abs(q.x)));
}

// wobbly halo lobes: polar domain-warped smooth union of ellipses
float haloSD(vec2 p, float ph) {
  vec2 d = p - VOID_C;
  float r = length(d) + 1e-3;
  float a = atan(d.y, d.x + 1e-5);
  float w = 0.020 * sin(2.0 * a + ph) + 0.014 * sin(3.0 * a - 2.0 * ph + 1.7)
          + 0.009 * sin(5.0 * a + ph + 0.6) + 0.006 * sin(7.0 * a - 3.0 * ph);
  vec2 q = p - d / r * w;
  float top = sdEll(rotCS(q - vec2(-0.20, 0.22), vec2(0.96593, 0.25882)), vec2(0.28, 0.50));
  float shl = sdEll(rotCS(q - vec2(-0.40, 0.05), vec2(0.61566, -0.78801)), vec2(0.46, 0.20));
  float lbb = sdEll(rotCS(q - vec2(0.46, -0.42), vec2(0.90631, 0.42262)), vec2(0.30, 0.26));
  float lbc = sdEll(rotCS(q - vec2(-0.33, -0.36), vec2(0.99027, -0.13917)), vec2(0.30, 0.12));
  float core = length(q - VOID_C) - 0.38;
  float s = smin(top, shl, 0.10);
  s = smin(s, lbb, 0.10);
  s = smin(s, lbc, 0.09);
  return smin(s, core, 0.10);
}

// flat banded disk (tilted ellipse rings), cut by the pointed lens
vec4 diskPix(vec2 p, float px, float t, float lensD) {
  vec2 q = rotCS(p - DISK_C, vec2(TILT.x, -TILT.y));
  vec2 e = vec2(q.x / DISK_A, q.y / DISK_B);
  float rho = length(e);
  float gr = max(length(vec2(e.x / DISK_A, e.y / DISK_B)) / max(rho, 1e-3), 1.0);
  float wr = px * gr;
  float a = clamp(0.5 - (rho - 1.0) / wr, 0.0, 1.0) * clamp(0.5 + (rho - RHO_IN) / wr, 0.0, 1.0);
  a *= cov(lensD + 0.010, px);
  float ws = clamp(wr * DSDRHO, 0.03, 0.5);
  float rc = rho * (1.0 + DOPPLER_K * clamp(e.x, -1.0, 1.0));
  return vec4(bandColor(rc, atan(e.y, e.x + 1e-5), ws, t), a);
}

// floating dot with hash-driven bobbing (integer time harmonics)
vec4 addDot(vec4 res, vec2 p, vec2 c, float r, vec3 col, float idx, float ph, float px, float dk) {
  float hs = hash11(idx * 7.13 + 1.7);
  float n = 1.0 + floor(hs * 2.0);
  float a0 = TAU * hash11(idx * 3.77 + 0.5);
  vec2 off = (0.010 + 0.006 * hs) * vec2(sin(n * ph + a0), cos(n * ph + 1.7 * a0));
  float d = length(p - c - off) - r;
  float a = cov(d, px);
  res = over(res, theme(col, dk), a);
  return over(res, C4, 0.55 * dk * a * (1.0 - cov(d + 1.5 * px, px)));
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 uv = fc / uSize * 2.0 - 1.0;
  uv.y = -uv.y;
  vec2 p = vec2(uv.x * uSize.x / uSize.y, uv.y);
  float px = 2.0 / uSize.y;
  float t = mod(uTime, LOOP_T);
  float ph = TAU * t / LOOP_T;
  float dk = clamp(uDark * DARK_BOOST * 1.6667, 0.0, 1.0);
  float edgeF = 1.0 - smoothstep(0.86, 0.995, max(abs(uv.x), abs(uv.y)));

  vec4 res = vec4(0.0);

  // halo: three stacked silhouettes
  float ln0 = lensSD(p);
  float s0 = smin(haloSD(p, ph), ln0, 0.05);
  float s1 = smin(haloSD(p, 2.0 * ph + 1.1), ln0, 0.05) + 0.045;
  float s2 = smin(haloSD(p, 3.0 * ph + 2.3), ln0, 0.05) + 0.100;
  float a0 = cov(s0, px);

  res = over(res, C3, 0.12 * dk * exp(-max(s0, 0.0) * 9.0) * edgeF * (1.0 - a0));
  res = over(res, theme(C0, dk), a0);
  res = over(res, theme(C1, dk), cov(s1, px) * a0);
  res = over(res, theme(C2, dk), cov(s2, px) * a0);
  res = over(res, theme(C3, dk), 0.85 * cov(abs(s1) - 0.0028, px) * a0);
  res = over(res, theme(C3, dk), 0.60 * cov(abs(s2) - 0.0022, px) * a0);
  res = over(res, theme(C2, dk), 0.70 * cov(abs(s0 + 0.020) - 0.0022, px) * a0);
  res = over(res, C4, 0.55 * dk * a0 * (1.0 - cov(s0 + 1.6 * px, px)));
  res = over(res, C4, 0.30 * dk * a0 * cov(s1, px) * (1.0 - cov(s1 + 1.4 * px, px)));

  // disk (full), then lensed images over it
  vec4 dsk = diskPix(p, px, t, ln0);
  res = over(res, theme(dsk.rgb, dk), dsk.a);

  float vr = length(p - VOID_C);
  vec4 g1 = glowPix(p, px, t);
  vec4 acc = vec4(g1.rgb * g1.a, g1.a);
  if (abs(vr - GLOW_R0) < 2.0 * px) {
    vec4 g2 = glowPix(p + vec2(0.37, 0.11) * px, px, t);
    vec4 g3 = glowPix(p + vec2(-0.21, -0.39) * px, px, t);
    acc += vec4(g2.rgb * g2.a, g2.a);
    acc += vec4(g3.rgb * g3.a, g3.a);
    acc /= 3.0;
  }
  vec3 glc = acc.a > 1e-4 ? acc.rgb / acc.a : vec3(0.0);
  res = over(res, theme(glc, dk), acc.a);

  // void and photon ring (pure black, white ring in both themes)
  res = over(res, vec3(0.0), cov(vr - GLOW_R0, px));
  res = over(res, vec3(1.0), cov(abs(vr - RING_R) - RING_W, px));

  // near half of the disk crosses in front of the void
  vec2 dq = rotCS(p - DISK_C, vec2(TILT.x, -TILT.y));
  float frontF = cov(dq.y, px) * cov(vr - (GLOW_R0 + 0.012), px);
  res = over(res, theme(dsk.rgb, dk), dsk.a * frontF);

  // floating dots
  res = addDot(res, p, vec2(-0.52, 0.44), 0.060, vec3(0.247, 0.435, 0.769), 0.0, ph, px, dk);
  res = addDot(res, p, vec2(0.31, 0.52), 0.055, vec3(0.184, 0.310, 0.588), 1.0, ph, px, dk);
  res = addDot(res, p, vec2(0.44, 0.37), 0.030, vec3(0.290, 0.471, 0.847), 2.0, ph, px, dk);
  res = addDot(res, p, vec2(-0.70, -0.03), 0.033, vec3(0.227, 0.384, 0.722), 3.0, ph, px, dk);
  res = addDot(res, p, vec2(-0.60, 0.18), 0.015, vec3(0.227, 0.384, 0.722), 4.0, ph, px, dk);
  res = addDot(res, p, vec2(-0.45, -0.50), 0.028, vec3(0.059, 0.106, 0.302), 5.0, ph, px, dk);
  res = addDot(res, p, vec2(0.0, -0.65), 0.033, vec3(0.078, 0.137, 0.373), 6.0, ph, px, dk);

  // outlined square: rotated-box SDF stroke, drifts and spins 90 deg per loop
  vec2 sc = vec2(-0.13, -0.54) + 0.010 * vec2(sin(ph + 0.7), cos(2.0 * ph));
  vec2 sq = rot2(p - sc, -(0.436 + 0.25 * ph));
  vec2 bd = abs(sq) - vec2(0.05);
  float sdb = length(max(bd, 0.0)) + min(max(bd.x, bd.y), 0.0);
  float sqA = cov(abs(sdb) - 0.004, px);
  res = over(res, theme(vec3(0.247, 0.447, 0.784), dk), sqA);
  res = over(res, C4, 0.55 * dk * sqA * (1.0 - cov(abs(sdb) - 0.004 + 1.5 * px, px)));

  // tone map (soft shoulder above 1), IGN dither, keep premultiplied
  float ign = fract(52.9829189 * fract(dot(fc, vec2(0.06711056, 0.00583715))));
  vec3 un = res.a > 1e-4 ? res.rgb / res.a : vec3(0.0);
  un = un / (1.0 + max(un - 1.0, 0.0));
  un = clamp(un + (ign - 0.5) / 255.0, 0.0, 1.0);
  fragColor = vec4(un * res.a, res.a);
}
