#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;

out vec4 fragColor;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

const float cosP = 0.94604;
const float sinP = 0.32404;
const float cosB = 0.99207;
const float sinB = 0.12566;

const vec3 cDeep = vec3(0.13, 0.08, 0.30);
const vec3 cMid = vec3(0.38, 0.26, 0.66);
const vec3 cLight = vec3(0.74, 0.65, 0.97);
const vec3 cHot = vec3(0.97, 0.94, 1.00);
const vec3 cCorona = vec3(0.48, 0.33, 0.88);
const vec3 cGlow = vec3(0.40, 0.27, 0.76);

float synHash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float synNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float a = synHash(i);
  float b = synHash(i + vec2(1.0, 0.0));
  float c = synHash(i + vec2(0.0, 1.0));
  float d = synHash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float synFbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * synNoise(p);
    p = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) * 2.02;
    a *= 0.5;
  }
  return v / 0.9375;
}

float synFbmL(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 3; i++) {
    v += a * synNoise(p);
    p = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) * 2.02;
    a *= 0.5;
  }
  return v / 0.875;
}

float synPlasma(vec2 p, float t) {
  vec2 q = vec2(synFbmL(p + vec2(0.0, t * 0.15)), synFbmL(p + vec2(5.2, 1.3) - t * 0.11));
  vec2 r = vec2(synFbmL(p + 3.5 * q + vec2(1.7, 9.2) + t * 0.09), synFbmL(p + 3.5 * q + vec2(8.3, 2.8) - t * 0.07));
  return synFbm(p + 3.0 * r);
}

vec3 synVoronoi(vec2 g, float spd) {
  vec2 ic = floor(g);
  float f1 = 9.0;
  float f2 = 9.0;
  float id = 0.0;
  for (int j = -1; j < 2; j++) {
    for (int k = -1; k < 2; k++) {
      vec2 c = ic + vec2(float(k), float(j));
      float h = synHash(c);
      vec2 q = c + 0.5 + 0.4 * vec2(sin(uTime * 0.7 * spd + h * TAU), cos(uTime * 0.6 * spd + h * 5.0));
      float d = distance(g, q);
      if (d < f1) { f2 = f1; f1 = d; id = h; }
      else if (d < f2) { f2 = d; }
    }
  }
  return vec3(f1, f2, id);
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  vec2 uv = (pos / uSize - 0.5) * 2.0;
  vec2 p = vec2(uv.x * (uSize.x / uSize.y), uv.y);

  float px = 2.0 / uSize.y;
  float r = length(p);
  float ang = atan(p.y, p.x);
  vec2 dir = p / max(r, 0.0001);

  float R = 0.42 * (1.0 + 0.012 * sin(uTime * 0.9) + 0.005 * sin(uTime * 1.7 + 1.3));

  vec2 sp = p / R;
  float sr2 = dot(sp, sp);
  float mu = sqrt(clamp(1.0 - sr2, 0.0, 1.0));

  vec3 discRGB = vec3(0.0);
  float discA = 0.0;

  if (sr2 < 1.12) {
    vec2 s2 = vec2(cosP * sp.x + sinP * sp.y, cosP * sp.y - sinP * sp.x);
    float yb = clamp(s2.y * cosB - mu * sinB, -1.0, 1.0);
    float zb = s2.y * sinB + mu * cosB;
    float lat = asin(yb);
    float lon = atan(s2.x, max(zb, 0.0001));
    float cl = sqrt(max(1.0 - yb * yb, 0.0));
    vec2 surf = vec2(lon * cl + uTime * 0.03, lat);

    vec2 gw = surf * 4.2;
    vec2 wp = vec2(synNoise(gw * 0.55 + vec2(uTime * 0.05, 3.3)), synNoise(gw * 0.55 + vec2(7.1, -uTime * 0.04))) - 0.5;
    vec3 v1 = synVoronoi(gw + 0.45 * wp, 1.0);
    vec3 v2 = synVoronoi(surf * 1.05 + vec2(11.0, 5.0), 0.35);
    float f1 = v1.x;
    float f2 = v1.y;
    float id = v1.z;
    float net = 1.0 - smoothstep(0.0, 0.22, v2.y - v2.x);

    float edge = smoothstep(0.0, 1.0, (f2 - f1) * 4.0);
    float cellB = 0.45 + 0.5 * sin(id * TAU + uTime * 0.8 + f1 * 3.0);
    float gran = mix(0.50, 1.0, edge) * (0.72 + 0.28 * cellB);
    gran = mix(0.80, gran, smoothstep(0.05, 0.50, mu));

    float plasma = synPlasma(surf * 1.15 + vec2(uTime * 0.02, -uTime * 0.015), uTime);
    float body = gran * (0.68 + 0.64 * plasma);
    body += 0.10 * net * smoothstep(0.2, 0.8, mu);

    float lp = lon + uTime * 0.03;
    float y33 = cl * cl * cl * cos(3.0 * lp - uTime * 0.55);
    float y42 = cl * cl * (7.0 * yb * yb - 1.0) * cos(2.0 * lp + uTime * 0.40);
    body *= 1.0 + 0.040 * y33 + 0.030 * y42;

    float absLat = abs(lat);
    float band = (1.0 - smoothstep(0.40, 0.75, absLat)) * smoothstep(0.04, 0.22, absLat);
    float sn = synNoise(surf * 1.9 + vec2(3.1, 7.7));
    float pen = (1.0 - smoothstep(0.19, 0.27, sn)) * band;
    float umb = (1.0 - smoothstep(0.10, 0.18, sn)) * band;
    body *= 1.0 - 0.40 * pen - 0.45 * umb;
    body += 0.16 * exp(-sr2 * 3.5);

    float T = 0.70 + 0.30 * clamp(body, 0.0, 1.3);
    float Ib = T * T;
    Ib *= Ib;
    float t = clamp(Ib * 0.90 + 0.25 * mu, 0.0, 1.5);
    vec3 col = mix(cDeep, cMid, smoothstep(0.10, 0.60, t));
    col = mix(col, cLight, smoothstep(0.55, 1.00, t));
    col = mix(col, cHot, smoothstep(0.95, 1.35, t));

    col *= 1.0 - vec3(0.78, 0.86, 0.55) * (1.0 - mu);
    float facula = pow(1.0 - mu, 3.0) * smoothstep(0.55, 0.80, plasma);
    col += cHot * 0.35 * facula;

    discA = 1.0 - smoothstep(R - px * 0.6, R + px * 0.4, r);
    discRGB = col * discA;
  }

  float cr = r / R;
  float corona = 0.0;
  float prom = 0.0;
  float cme = 0.0;

  if (cr > 0.95) {
    float kr = cr - 1.0;
    float kp = max(kr, 0.0);
    float c2 = cr * cr;
    float c6 = c2 * c2 * c2;
    float c16 = c6 * c6 * c2 * c2;
    float dens = (1.55 / c6 + 2.99 / c16) / 4.54;
    float falloff = 0.65 * exp(-kr * 3.0) + 0.15 * dens + 0.20 / c2;

    float an = ang * 3.0 + uTime * 0.05;
    float n1 = synFbmL(vec2(cos(an), sin(an)) * 1.5 + vec2(0.0, cr * 0.6));
    float n2 = synFbmL(vec2(cos(an * 2.0), sin(an * 2.0)) * 2.5 - vec2(uTime * 0.03, 0.0));

    float ray = pow(0.5 + 0.5 * sin(ang * 9.0 + n1 * 6.0 + kr * 2.2 + uTime * 0.35), 3.0);
    float flare = pow(0.5 + 0.5 * sin(ang * 4.0 - uTime * 0.22 + n2 * 4.0), 6.0);

    float eq = abs(dir.y * cosP - dir.x * sinP);
    float wq = eq / (0.42 / (1.0 + 1.4 * kp) + 0.04);
    float helmet = exp(-wq * wq) * (0.6 + 0.4 * n1);
    float plume = pow(0.5 + 0.5 * sin(ang * 23.0 + n1 * 5.0 - kr * 1.2), 10.0) * pow(eq, 5.0) * exp(-kp * 1.8);

    corona = falloff * (0.30 + 0.45 * n1 + 0.38 * ray) + 0.45 * flare * (0.5 + 0.5 * n2) * exp(-kp * 1.7) + 0.28 * helmet * exp(-kp * 1.3) + 0.30 * plume;
    corona *= smoothstep(0.95, 1.12, cr);

    float a5 = ang / TAU * 5.0 + uTime * 0.004;
    float hh = synHash(vec2(mod(floor(a5), 5.0), 3.7));
    float apex = (0.05 + 0.13 * hh) * (0.8 + 0.2 * sin(uTime * 0.5 + hh * TAU));
    float dd = kr - apex * pow(max(sin(PI * fract(a5)), 0.0), 0.8);
    prom = exp(-dd * dd * 420.0) * smoothstep(0.2, 0.5, hh) * smoothstep(0.985, 1.03, cr);

    float ph = fract(uTime / 26.0);
    float ca = synHash(vec2(floor(uTime / 26.0), 1.7)) * TAU;
    float da = 1.0 - dot(dir, vec2(cos(ca), sin(ca)));
    float cw = exp(-da * 30.0);
    float rc = 1.02 + 0.85 * (1.0 - exp(-ph * 2.6));
    float shell = exp(-(cr - rc) * (cr - rc) * 160.0);
    float fade = smoothstep(0.0, 0.07, ph) * (1.0 - smoothstep(0.35, 0.90, ph));
    cme = cw * (shell * 0.55 + 0.35 * exp(-kp * 5.0) * exp(-ph * 5.0)) * fade * smoothstep(0.98, 1.02, cr);
  }

  float glow = exp(-max(r - R, 0.0) * 4.5) * 0.5;
  float rd = (r - R) / (R * 0.045);
  float rim = exp(-rd * rd) * 0.5;

  vec3 coronaCol = mix(cCorona, cLight, clamp(corona * 0.8, 0.0, 1.0));
  float coronaA = clamp(corona, 0.0, 1.0) * 0.75;
  float promA = clamp(prom, 0.0, 1.0) * 0.6;
  float cmeA = clamp(cme, 0.0, 1.0) * 0.6;

  float edgeFade = 1.0 - smoothstep(0.78, 1.0, r);

  vec3 rgb = discRGB + coronaCol * coronaA + cLight * (promA + cmeA) + cGlow * glow + mix(cLight, cHot, 0.5) * rim;
  rgb = min(rgb * edgeFade, vec3(1.0));
  float a = clamp(discA + (coronaA * 0.7 + (promA + cmeA) * 0.7 + glow * 0.6 + rim * 0.6) * (1.0 - discA), 0.0, 1.0) * edgeFade;

  fragColor = vec4(rgb, a);
}
