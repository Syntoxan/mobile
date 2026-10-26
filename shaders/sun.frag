#version 460 core
precision highp float;
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;

out vec4 fragColor;

const float PI = 3.14159265359;
const float TAU = 6.28318530718;

const float THEME = 0.0;
const float SHADOW_R = 0.262;
const float B_CRIT = 2.59807621;
const float R_IN = 1.85;
const float R_OUT = 7.6;
const float FOV_D = 42.0;
const float DOPPLER = 0.42;
const float DISK_SPEED = 1.0;
const float LOOP_T = 90.0;
const float W_LOOP = TAU / LOOP_T;
const float cosR = 0.95318;
const float sinR = 0.30242;

const float SPIN_DIR = 1.0;
const float TEX_AA = 1.0;
const float GRAIN_KEEP = 0.35;
const float STAR_AA = 1.0;
const float DITHER = 1.0;

const float H_FAR = 0.22;
const float H_NEAR = 0.11;
const float B_FAR = 8.6;
const int MAX_STEPS = 96;

const vec3 cDeep = vec3(0.13, 0.08, 0.30);
const vec3 cMid = vec3(0.38, 0.26, 0.66);
const vec3 cLight = vec3(0.74, 0.65, 0.97);
const vec3 cHot = vec3(0.97, 0.94, 1.00);

float bhHash(vec2 p) {
  vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, vec3(p3.y, p3.z, p3.x) + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float bhNoiseP(vec2 p, float per) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float x0 = mod(i.x, per);
  float x1 = mod(i.x + 1.0, per);
  float a = bhHash(vec2(x0, i.y));
  float b = bhHash(vec2(x1, i.y));
  float c = bhHash(vec2(x0, i.y + 1.0));
  float d = bhHash(vec2(x1, i.y + 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float herm(float s, float p0, float m0, float p1, float m1) {
  float s2 = s * s;
  float s3 = s2 * s;
  return (2.0 * s3 - 3.0 * s2 + 1.0) * p0 + (s3 - 2.0 * s2 + s) * m0
       + (3.0 * s2 - 2.0 * s3) * p1 + (s3 - s2) * m1;
}

float hermD(float s, float p0, float m0, float p1, float m1) {
  float s2 = s * s;
  return (6.0 * s2 - 6.0 * s) * p0 + (3.0 * s2 - 4.0 * s + 1.0) * m0
       + (6.0 * s - 6.0 * s2) * p1 + (3.0 * s2 - 2.0 * s) * m1;
}

float kepler(float r, float tt) {
  return DISK_SPEED * 0.9 * inversesqrt(r * r * r) * tt / TAU;
}

float octW(float cells) {
  return mix(1.0, GRAIN_KEEP, smoothstep(0.5, 1.5, TEX_AA * cells));
}

vec3 diskRamp(float t) {
  vec3 g = mix(vec3(0.10, 0.035, 0.020), vec3(0.50, 0.17, 0.05), smoothstep(0.00, 0.28, t));
  g = mix(g, vec3(0.93, 0.50, 0.17), smoothstep(0.22, 0.52, t));
  g = mix(g, vec3(1.00, 0.80, 0.52), smoothstep(0.48, 0.80, t));
  g = mix(g, vec3(1.00, 0.96, 0.88), smoothstep(0.78, 1.10, t));
  vec3 pc = mix(cDeep * 0.5, cMid, smoothstep(0.00, 0.40, t));
  pc = mix(pc, cLight, smoothstep(0.35, 0.80, t));
  pc = mix(pc, cHot, smoothstep(0.78, 1.10, t));
  return mix(g, pc, THEME);
}

float diskTex(float r, float rev, float tt, vec2 fp) {
  float k = kepler(r, tt);
  float x = rev + SPIN_DIR * k;
  float ex = fp.y + 1.5 * k / r * fp.x;
  float n1 = mix(0.5, bhNoiseP(vec2(x * 3.0, r * 2.4 + 1.7), 3.0), octW(3.0 * ex + 2.4 * fp.x));
  x += (n1 - 0.5) * 0.05;
  float n2 = mix(0.5, bhNoiseP(vec2(x * 7.0 + 3.0, r * 7.0 + 8.0), 7.0), octW(7.0 * ex + 7.0 * fp.x));
  float n3 = mix(0.5, bhNoiseP(vec2(x * 11.0 + 11.0, r * 20.0 + 2.0), 11.0), octW(11.0 * ex + 20.0 * fp.x));
  float n4 = mix(0.5, bhNoiseP(vec2(x * 23.0 + 5.0, r * 52.0 + 9.0), 23.0), octW(23.0 * ex + 52.0 * fp.x));
  return 0.22 * n1 + 0.30 * n2 + 0.28 * n3 + 0.20 * n4;
}

float sparkLayer(float r, float rev, float tt, vec2 fp) {
  float row = floor(r * 60.0);
  float rc = (row + 0.5) / 60.0;
  float k = kepler(rc, tt);
  float c = (rev + SPIN_DIR * k) * 900.0;
  float ci = floor(c);
  float cf = c - ci;
  float g0 = bhHash(vec2(mod(ci, 900.0), row));
  float g1 = bhHash(vec2(mod(ci + 1.0, 900.0), row));
  g0 *= g0; g0 *= g0; g0 *= g0; g0 *= g0;
  g1 *= g1; g1 *= g1; g1 *= g1; g1 *= g1;
  float sp = mix(g0, g1, cf);
  float cells = 900.0 * (fp.y + 1.5 * k / rc * fp.x) + 60.0 * fp.x;
  return mix(sp, 1.0 / 17.0, smoothstep(8.0, 30.0, TEX_AA * cells));
}

float rimLayer(float rev, float tt) {
  float k = kepler(6.5, tt);
  return bhNoiseP(vec2((rev + SPIN_DIR * k) * 9.0, 3.0), 9.0);
}

vec4 diskShade(float r, float az, float g, float mu, vec2 fp, float tl) {
  float rev = az / TAU + 0.5;
  float x = R_IN / r;

  float tA = tl;
  float tB = mod(tl + 0.5 * LOOP_T, LOOP_T);
  float wA = 0.5 - 0.5 * cos(W_LOOP * tl);
  float wB = 1.0 - wA;
  float nrm = inversesqrt(wA * wA + wB * wB);

  float tex = clamp(0.5 + (wA * (diskTex(r, rev, tA, fp) - 0.5) + wB * (diskTex(r, rev, tB, fp) - 0.5)) * nrm, 0.0, 1.0);
  float rj = clamp(0.5 + (wA * (rimLayer(rev, tA) - 0.5) + wB * (rimLayer(rev, tB) - 0.5)) * nrm, 0.0, 1.0);
  float rcut = R_OUT * (0.80 + 0.20 * rj);

  float inner = smoothstep(R_IN, R_IN + 0.12, r);
  float outer = 1.0 - smoothstep(0.55 * rcut, rcut, r);
  float dens = inner * outer;

  float Tem = pow(x, 0.75);
  float streak = pow(tex, 1.9) * 2.4;
  float gI = pow(max(g, 0.05), 4.0 * DOPPLER) * (0.24 + 0.76 * mu);
  float gT = pow(max(g, 0.05), 0.6 * DOPPLER + 0.2);

  float grain = wA * sparkLayer(r, rev, tA, fp) + wB * sparkLayer(r, rev, tB, fp);
  float spark = grain * 2.0 * smoothstep(3.5, 7.0, r);

  float I = (pow(x, 1.9) * (0.50 + 1.20 * streak) + 0.10 * streak * x) * gI + spark * 0.25 * dens;
  float t = clamp(Tem * gT * (0.45 + 0.50 * streak) + 0.30 * I, 0.0, 1.3);
  vec3 col = diskRamp(t) * I * 6.0;
  float alpha = clamp(dens * (0.55 + 0.75 * tex + 0.35 * x), 0.0, 0.97);
  return vec4(col, alpha);
}

float starField(vec2 pos, float sr, float st, float tl) {
  vec2 gq = pos * 30.0;
  vec2 ic = floor(gq);
  vec2 fc = gq - ic;
  float hs = bhHash(ic + 7.0);
  if (hs <= 0.975) return 0.0;
  vec2 sp = vec2(bhHash(ic + 17.0), bhHash(ic + 31.0)) * 0.6 + 0.2;
  float rad = 0.0016 + 0.3 * 2.0 / uSize.y * (B_CRIT / SHADOW_R) / FOV_D;
  float a2 = rad * rad;
  float vr = a2 + 0.25 * STAR_AA * STAR_AA * sr * sr;
  float vt = a2 + 0.25 * STAR_AA * STAR_AA * st * st;
  vec2 dv = (fc - sp) / 30.0;
  vec2 ax = pos / max(length(pos), 0.00001);
  float dr = dot(dv, ax);
  float dt = dv.y * ax.x - dv.x * ax.y;
  float amp = a2 * inversesqrt(vr * vt);
  float wk = W_LOOP * (29.0 + floor(bhHash(ic + 9.0) * 29.0));
  float tw = 0.75 + 0.25 * sin(wk * tl + TAU * bhHash(ic + 5.0));
  return exp(-dr * dr / vr - dt * dt / vt) * amp * (0.35 + 0.65 * bhHash(ic + 3.0)) * tw;
}

vec4 trace(vec2 p, float tl, float pixB) {
  float el = 0.0873 + 0.006 * sin(3.0 * W_LOOP * tl);
  float sE = sin(el);
  float cE = cos(el);

  vec2 q = vec2(p.x, -p.y);
  vec2 qr = vec2(cosR * q.x + sinR * q.y, -sinR * q.x + cosR * q.y);
  vec2 bv = qr * (B_CRIT / SHADOW_R);
  float b = max(length(bv), 0.04);
  vec2 bd = bv / b;

  vec3 e1 = vec3(0.0, sE, cE);
  vec3 e2 = vec3(bd.x, bd.y * cE, -bd.y * sE);
  float nextC = mod(atan(-sE, e2.y), PI);

  float invb2 = 1.0 / (b * b);
  float u = 0.0;
  float w = 1.0 / b;
  float du = 0.0;
  float dw = -invb2;
  float phi = 0.0;
  float T = 1.0;
  vec3 col = vec3(0.0);
  bool captured = false;
  bool escaped = false;
  float phiEnd = 0.0;
  float dphiEnd = 0.0;

  bool far = b > B_FAR;
  if (far) {
    float xb = 1.0 / b;
    phiEnd = PI + xb * (2.0 + xb * (2.94381042 + xb * (5.44201819 + xb * (8.05556728 + xb * 45.08112548))));
    dphiEnd = xb * xb * (2.0 + xb * (5.88762084 + xb * (16.32605457 + xb * (32.22226912 + xb * 225.4056274))));
    escaped = true;
  }

  for (int i = 0; i < MAX_STEPS; i++) {
    if (far) break;
    float h = H_FAR + (H_NEAR - H_FAR) * clamp((u - 0.04) * 4.5, 0.0, 1.0);

    float k1w = -u + 1.5 * u * u;
    float u2 = u + 0.5 * h * w;
    float w2 = w + 0.5 * h * k1w;
    float k2w = -u2 + 1.5 * u2 * u2;
    float u3 = u + 0.5 * h * w2;
    float w3 = w + 0.5 * h * k2w;
    float k3w = -u3 + 1.5 * u3 * u3;
    float u4 = u + h * w3;
    float w4 = w + h * k3w;
    float k4w = -u4 + 1.5 * u4 * u4;
    float u1 = u + h / 6.0 * (w + 2.0 * w2 + 2.0 * w3 + w4);
    float w1 = w + h / 6.0 * (k1w + 2.0 * k2w + 2.0 * k3w + k4w);

    float dum = du + 0.5 * h * dw;
    float dwm = dw + 0.5 * h * (3.0 * u - 1.0) * du;
    float du1 = du + h * dwm;
    float dw1 = dw + h * (3.0 * u2 - 1.0) * dum;

    if (u1 > 0.2) {
      float gu = 2.0 * u1 - 3.0 * u1 * u1;
      float gw = 2.0 * w1;
      float gg = w1 * w1 + u1 * u1 - u1 * u1 * u1 - invb2;
      float lm = gg / max(gu * gu + gw * gw, 0.001);
      u1 -= lm * gu;
      w1 -= lm * gw;
    }
    float phi1 = phi + h;

    if (nextC <= phi1) {
      float s = (nextC - phi) / h;
      float uc = herm(s, u, h * w, u1, h * w1);
      if (uc > 0.02 && uc < 0.95) {
        float r = 1.0 / uc;
        if (r > R_IN * 0.97 && r < R_OUT) {
          float wc = mix(w, w1, s);
          float duc = herm(s, du, h * dw, du1, h * dw1);
          float sn = sin(nextC);
          float cn = cos(nextC);
          vec3 er = cn * e1 + sn * e2;
          vec3 et = -sn * e1 + cn * e2;
          float az = atan(er.z, er.x);
          float nt = b * uc * sqrt(max(1.0 - uc, 0.0));
          float nr = sqrt(max(1.0 - nt * nt, 0.0));
          float sg = wc > 0.0 ? nr : -nr;
          vec3 nph = er * sg - et * nt;
          float vo = min(sqrt(0.5 / max(r - 1.0, 0.05)), 0.92);
          vec3 vd = vec3(er.z, 0.0, -er.x) / max(sqrt(er.x * er.x + er.z * er.z), 0.0001);
          float gam = 1.0 / sqrt(1.0 - vo * vo);
          float g = sqrt(max(1.0 - uc, 0.0)) / (gam * (1.0 - dot(nph, vd) * vo));
          float mu = min(abs(nph.y) * 3.2, 1.0);

          float dcdp = sE * cE * bd.x / (sE * sE + cE * cE * bd.y * bd.y);
          vec3 der = dcdp * et + sn * vec3(-bd.y, bd.x * cE, -bd.x * sE);
          float daz = er.x * der.z - er.z * der.x;
          float drdb = -r * r * duc;
          float drdp = -r * r * wc * dcdp;
          vec2 fp = vec2(pixB * (abs(drdb) + abs(drdp) / b), pixB * abs(daz) / (b * TAU));

          vec4 dk = diskShade(r, az, g, mu, fp, tl);
          col += T * dk.xyz * dk.w;
          T *= 1.0 - dk.w;
        }
      }
      nextC += PI;
    }

    if (u1 >= 1.0) { captured = true; break; }
    if (u1 <= 0.0) {
      float se = u / max(u - u1, 0.00001);
      se = clamp(se - herm(se, u, h * w, u1, h * w1) / min(hermD(se, u, h * w, u1, h * w1), -0.000001), 0.0, 1.0);
      se = clamp(se - herm(se, u, h * w, u1, h * w1) / min(hermD(se, u, h * w, u1, h * w1), -0.000001), 0.0, 1.0);
      phiEnd = phi + h * se;
      float we = mix(w, w1, se);
      dphiEnd = abs(mix(du, du1, se) / min(we, -0.0001));
      escaped = true;
      break;
    }
    if (T < 0.02) break;
    u = u1;
    w = w1;
    du = du1;
    dw = dw1;
    phi = phi1;
  }

  float a = 0.0;
  if (escaped) {
    vec3 sv = normalize(vec3(sin(phiEnd) * bd + bv / FOV_D, -cos(phiEnd)));
    float lam = sqrt(2.0 / max(1.0 + sv.z, 0.0001));
    vec2 spos = sv.xy * lam;
    float cs = sqrt(0.5 * (1.0 + sv.z));
    float sr = pixB * (min(dphiEnd, 1000.0) + 1.0 / FOV_D) * cs;
    float st = pixB / b * length(spos);
    col += T * vec3(1.0, 0.92, 0.84) * starField(spos, sr, st, tl) * 0.7;
  } else {
    a = 1.0;
  }
  float m = max(max(col.x, col.y), col.z);
  a = max(a, clamp(m, 0.0, 1.0));
  return vec4(col, a);
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  vec2 uv = (pos / uSize - 0.5) * 2.0;
  vec2 p = vec2(uv.x * (uSize.x / uSize.y), uv.y);
  float px = 2.0 / uSize.y;
  float rr = length(p);

  if (rr >= 1.0) {
    fragColor = vec4(0.0);
    return;
  }

  float tl = mod(uTime, LOOP_T);
  float pixB = px * (B_CRIT / SHADOW_R);

  int ns = 1;
  if (abs(rr - SHADOW_R) < 3.0 * px) ns = 4;
  vec4 acc = vec4(0.0);
  for (int s = 0; s < 4; s++) {
    if (s >= ns) break;
    vec2 o = vec2(0.0);
    float fps = 1.0;
    if (ns > 1) {
      if (s == 0) o = vec2(-0.125, -0.375);
      if (s == 1) o = vec2(0.375, -0.125);
      if (s == 2) o = vec2(-0.375, 0.125);
      if (s == 3) o = vec2(0.125, 0.375);
      fps = 0.55;
    }
    acc += trace(p + o * px, tl, pixB * fps);
  }
  acc /= float(ns);

  vec3 rgb = acc.xyz;
  float a = acc.w;

  vec2 q = vec2(p.x, -p.y);
  vec2 qr = vec2(cosR * q.x + sinR * q.y, -sinR * q.x + cosR * q.y);
  float halo = exp(-max(rr - 0.9 * SHADOW_R, 0.0) * 7.0) * 0.85;
  float hline = exp(-abs(qr.y) * 22.0) * exp(-max(abs(qr.x) - 0.12, 0.0) * 4.0) * 0.16;
  float hin = smoothstep(0.80 * SHADOW_R, 1.10 * SHADOW_R, rr);
  float breathe = 1.0 + 0.04 * sin(10.0 * W_LOOP * tl);
  vec3 hc = diskRamp(0.50);
  vec3 bloom = hc * (halo + hline) * hin * breathe;

  float inside = 1.0 - smoothstep(0.96 * SHADOW_R, 1.0 * SHADOW_R, rr);
  float pr = (rr - 0.915 * SHADOW_R) / (SHADOW_R * 0.012);
  vec3 innerGlow = hc * (0.05 * exp(-rr * 3.0) + 0.22 * exp(-pr * pr)) * inside;
  rgb += bloom * (1.0 - min(a, 1.0) * 0.5) + innerGlow * (0.5 + 0.5 * smoothstep(0.0, 1.0, a));

  float m = max(max(rgb.x, rgb.y), rgb.z);
  float tm = 1.0 - exp(-m * 1.1);
  rgb = rgb * (tm / max(m, 0.0001));
  rgb = mix(rgb, vec3(1.0, 0.97, 0.92) * tm, smoothstep(0.45, 0.95, tm) * 0.80 * (1.0 - THEME));

  float mm = max(max(rgb.x, rgb.y), rgb.z);
  a = max(a, mm);

  float edgeFade = 1.0 - smoothstep(0.78, 1.0, rr);
  rgb = min(rgb * edgeFade, vec3(1.0));
  a = clamp(a * edgeFade, 0.0, 1.0);

  if (a > 0.004) {
    float ign = fract(52.9829189 * fract(dot(pos, vec2(0.06711056, 0.00583715))));
    float dn = DITHER * (ign - 0.5) / 255.0;
    rgb = clamp(rgb + dn, vec3(0.0), vec3(1.0));
    a = max(clamp(a + dn, 0.0, 1.0), max(max(rgb.x, rgb.y), rgb.z));
  }

  fragColor = vec4(rgb, a);
}
