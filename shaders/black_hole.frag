#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;   // seconds
uniform float uDark;   // 1.0 = dark mode, 0.0 = light mode

out vec4 fragColor;

#define VIEW 376.0
#define CAP 28.0
#define PI2 6.28318530718

float pw(float x, float n)
{
    return pow(max(x, 0.0), n);
}

float hash21(vec2 q)
{
    q = fract(q * vec2(123.34, 456.21));
    q += dot(q, q + 45.32);
    return fract(q.x * q.y);
}

vec3 neon(float ph)
{
    float cr = 0.5 + 0.5 * cos(PI2 * ph);
    return vec3(cr, 0.95 - 0.8 * cr, 1.0 - 0.18 * cr);
}

// r.x = best dist^2, r.y = inside sign, r.zw = vector from nearest edge point to p
vec4 synBez(vec2 p, vec4 r, vec2 a, vec2 b, vec2 c, vec2 d)
{
    vec2 lo = min(min(a, b), min(c, d));
    vec2 hi = max(max(a, b), max(c, d));
    vec2 gap = max(max(lo - p, p - hi), vec2(0.0));
    bool needD = dot(gap, gap) < r.x;
    bool needX = (p.y >= lo.y) && (p.y <= hi.y) && (p.x < hi.x);
    if (!needD && !needX) return r;

    float dm = r.x;
    float s = r.y;
    vec2 qb = r.zw;
    vec2 g = a;
    for (int i = 1; i <= 16; i++)
    {
        float t = float(i) / 16.0;
        float m = 1.0 - t;
        vec2 h = m * m * m * a + 3.0 * m * m * t * b + 3.0 * m * t * t * c + t * t * t * d;
        vec2 e = h - g;
        if (needD)
        {
            vec2 w = p - g;
            vec2 q = w - e * clamp(dot(w, e) / max(dot(e, e), 1.0e-9), 0.0, 1.0);
            float dq = dot(q, q);
            if (dq < dm)
            {
                dm = dq;
                qb = q;
            }
        }
        if ((g.y > p.y) != (h.y > p.y) && p.x < g.x + (p.y - g.y) * e.x / e.y) s = -s;
        g = h;
    }
    return vec4(dm, s, qb);
}

#define SYN_B(a, b, c, d, e, f) r = synBez(p, r, u, vec2(a, b), vec2(c, d), vec2(e, f)); u = vec2(e, f);

void main()
{
    vec2 C = vec2(256.0, 257.0);
    vec2 p = FlutterFragCoord().xy / uSize * VIEW + (C - 0.5 * VIEW);
    float k = VIEW / uSize.x;

    vec2 u = vec2(284.99, 329.19);
    vec4 r = vec4(CAP * CAP, 1.0, 0.0, 0.0);
    SYN_B(302.87,327.18,322.02,322.78,335.84,310.47)SYN_B(348.59,299.11,354.88,282.84,356.82,266.17)
    SYN_B(357.04,264.32,357.05,262.45,357.19,260.59)SYN_B(357.90,251.17,357.60,241.81,354.78,232.73)
    SYN_B(352.07,224.01,347.26,216.39,341.26,209.58)SYN_B(342.25,206.26,343.20,202.95,343.74,199.52)
    SYN_B(344.87,192.40,344.43,184.47,342.63,177.50)SYN_B(342.10,175.45,340.80,168.95,338.95,168.00)
    SYN_B(336.30,166.64,329.69,168.12,326.83,168.83)SYN_B(315.72,171.55,305.69,177.69,296.16,183.80)
    SYN_B(286.87,181.97,277.69,179.80,268.20,179.11)SYN_B(254.77,178.13,241.02,178.70,227.78,181.22)
    SYN_B(223.75,181.98,219.77,183.00,215.76,183.83)SYN_B(206.15,177.68,195.99,171.53,184.78,168.83)
    SYN_B(181.83,168.12,175.63,166.69,172.81,167.89)SYN_B(170.61,168.84,169.30,175.61,168.79,177.87)
    SYN_B(166.18,189.36,166.75,198.32,170.30,209.52)SYN_B(164.69,216.16,159.96,223.10,157.16,231.40)
    SYN_B(153.47,242.36,153.29,254.16,154.72,265.54)SYN_B(156.78,281.86,161.63,297.23,173.98,308.82)
    SYN_B(188.13,322.12,207.66,327.30,226.52,329.24)SYN_B(220.63,336.18,217.70,341.12,216.64,350.30)
    SYN_B(214.35,351.17,212.10,352.09,209.74,352.76)SYN_B(197.50,356.18,185.36,354.37,176.10,345.28)
    SYN_B(172.94,342.18,170.85,338.29,168.27,334.74)SYN_B(163.93,328.78,157.47,323.49,150.14,321.88)
    SYN_B(146.79,321.14,142.83,320.38,139.67,322.27)SYN_B(136.94,323.90,139.44,326.71,141.04,328.09)
    SYN_B(142.77,329.58,144.70,330.70,146.54,332.01)SYN_B(151.10,335.28,154.86,339.80,157.72,344.60)
    SYN_B(161.32,350.65,163.13,357.59,167.73,363.04)SYN_B(179.87,377.46,198.95,378.23,216.04,374.60)
    SYN_B(216.05,382.05,216.12,389.52,216.14,396.98)SYN_B(216.15,400.65,216.58,404.45,213.60,407.17)
    SYN_B(211.48,409.11,208.49,409.35,205.76,408.96)SYN_B(201.62,408.37,190.65,403.48,186.57,401.49)
    SYN_B(162.20,389.57,141.00,372.59,125.18,350.42)SYN_B(113.55,334.10,105.03,315.71,100.29,296.24)
    SYN_B(96.81,281.95,95.29,266.54,96.17,251.85)SYN_B(99.70,192.42,135.65,140.83,190.12,116.77)
    SYN_B(204.28,110.52,219.39,106.07,234.76,104.18)SYN_B(252.93,101.94,271.50,102.52,289.44,106.19)
    SYN_B(349.26,118.44,399.15,166.10,412.17,226.03)SYN_B(415.20,239.99,416.69,254.38,415.77,268.68)
    SYN_B(414.74,284.60,411.62,300.56,405.72,315.42)SYN_B(391.89,350.25,366.68,379.14,333.69,397.07)
    SYN_B(326.29,401.10,318.57,404.45,310.65,407.32)SYN_B(307.03,408.63,302.85,410.07,299.14,408.17)
    SYN_B(297.27,407.21,296.07,405.46,295.50,403.48)SYN_B(294.65,400.57,295.18,388.15,295.23,384.33)
    SYN_B(295.30,377.67,295.33,371.00,295.33,364.33)SYN_B(295.33,354.38,295.15,344.14,289.69,335.40)
    SYN_B(288.31,333.18,286.64,331.21,284.99,329.19)

    float dw = sqrt(r.x) * r.y;
    float aa = clamp(0.5 - dw / k, 0.0, 1.0);
    float depth = max(-dw, 0.0);
    float away = max(dw, 0.0);
    vec2 n = r.zw * r.y / max(length(r.zw), 1.0e-4);

    float T = uTime;
    float dk = uDark;
    float lod = clamp((2.2 - k) / 1.0, 0.0, 1.0);
    float ign = smoothstep(0.0, 1.4, T);
    vec2 uv = (p - C) / 160.0;
    float rad = length(uv);
    float ang = atan(uv.y, uv.x);
    float turn = ang / PI2;

    // ---- 3D bevel lighting (normal comes free from the SDF)
    float bt = clamp(depth / 12.0, 0.0, 1.0);
    float tilt = (1.0 - bt) * (1.0 - bt) * 1.7;
    vec3 N = normalize(vec3(n * tilt, 1.0));
    vec3 V = vec3(0.0, 0.0, 1.0);
    float la = T * 0.55;
    vec3 L1 = normalize(vec3(cos(la) * 0.8, sin(la) * 0.8, 0.55));
    vec3 L2 = normalize(vec3(-0.6, -0.65, 0.5));
    float dif = clamp(dot(N, L1) * 0.6 + dot(N, L2) * 0.4, 0.0, 1.0);
    float s1 = pw(dot(N, normalize(L1 + V)), 36.0);
    float s2 = pw(dot(N, normalize(L2 + V)), 36.0);
    float fres = pw(1.0 - N.z, 1.5);

    // ---- metal body
    float conic = 0.5 + 0.5 * cos(ang * 2.0 - T * 0.4 + rad * 1.6);
    conic *= conic;
    float brush = 0.5 + 0.5 * sin(rad * 110.0 + sin(ang * 7.0) * 2.0);
    float lum = 0.28 + 0.36 * conic + 0.32 * dif - 0.10 * uv.y + 0.07 * (brush - 0.5) * lod;
    vec3 cLo = mix(vec3(0.035, 0.045, 0.075), vec3(0.30, 0.34, 0.44), dk);
    vec3 cHi = mix(vec3(0.42, 0.46, 0.62), vec3(0.93, 0.96, 1.00), dk);
    vec3 body = mix(cLo, cHi, clamp(lum, 0.0, 1.0));
    vec3 aur = neon(rad * 0.45 - T * 0.05 + uv.x * 0.2);
    vec3 irid = neon(fres * 1.3 + turn + T * 0.07);
    body *= 0.86 + 0.28 * aur;
    body += aur * mix(0.09, 0.05, dk) * (0.35 + 0.65 * conic);
    body += irid * fres * mix(0.55, 0.40, dk);
    body += vec3(1.0) * (s1 + 0.7 * s2) * mix(0.90, 0.75, dk);

    // ---- engraved lines + micro hatch
    vec3 gcol = mix(vec3(0.70, 0.80, 1.00), vec3(0.04, 0.05, 0.09), dk);
    float gw = max(1.0, k * 0.9);
    float x1 = (depth - 17.0) / gw;
    float x2 = (depth - 20.5) / (gw * 0.7);
    float groove = exp(-x1 * x1) * 0.55 + exp(-x2 * x2) * 0.25;
    float band = smoothstep(22.5, 23.5, depth) * (1.0 - smoothstep(26.0, 27.0, depth));
    float hatch = step(0.5, fract((p.x + p.y) / 4.0));
    body = mix(body, gcol, clamp(groove * 0.6 + band * hatch * 0.22 * lod, 0.0, 1.0));

    // ---- light sweep + sparkles
    float sd = dot(uv, vec2(0.7071, -0.7071)) - (-1.9 + fract(T / 4.2) * 5.2);
    float sweep = exp(-sd * sd * 24.0) + 0.6 * exp(-(sd + 0.24) * (sd + 0.24) * 260.0);
    body += mix(vec3(1.0), irid, 0.5) * sweep * mix(0.50, 0.30, dk) * ign * (0.55 + 1.2 * fres);
    vec2 cp = p / 13.0;
    vec2 cid = floor(cp);
    vec2 cf = fract(cp) - 0.5;
    float h1 = hash21(cid);
    vec2 dq = cf - (vec2(hash21(cid + 17.3), hash21(cid + 41.7)) - 0.5) * 0.24;
    float tw = pw(0.5 + 0.5 * sin(T * (1.3 + h1 * 2.2) + h1 * 60.0), 8.0);
    float star = exp(-dot(dq, dq) * 420.0)
        + 0.55 * max(0.0, 1.0 - 14.0 * abs(dq.x)) * max(0.0, 1.0 - 3.4 * abs(dq.y))
        + 0.55 * max(0.0, 1.0 - 14.0 * abs(dq.y)) * max(0.0, 1.0 - 3.4 * abs(dq.x));
    body += vec3(1.0) * step(0.84, h1) * tw * star * 0.95;

    // ---- neon aura outside + hologram haze inside the cat
    float pulse = pw(0.5 + 0.5 * cos(ang - T * 1.1), 6.0);
    vec3 hue = neon(turn + T * 0.08 + away * 0.004);
    float hot = exp(-away / 1.3);
    float glow = (0.55 * exp(-away / 3.5) + 0.40 * exp(-away / 11.0)) * (0.45 + 1.1 * pulse);
    glow *= (1.0 - smoothstep(CAP * 0.55, CAP, away)) * ign * mix(0.60, 1.0, dk);
    vec3 gC = clamp(hue * mix(0.80, 1.0, dk) + vec3(hot * 0.5 * dk), 0.0, 1.0);
    float gA = clamp(glow, 0.0, 0.95);

    float inDisc = 1.0 - smoothstep(0.90, 1.0, length((p - C) / vec2(160.0, 154.0)));
    float scan = 0.5 + 0.5 * sin(p.y * 0.9 - T * 2.4);
    float holeA = inDisc * (0.06 + 0.06 * scan * lod) * ign;
    vec3 holeC = mix(vec3(0.20, 0.62, 1.00), vec3(0.78, 0.32, 1.00), clamp(0.5 + 0.5 * uv.y, 0.0, 1.0)) * mix(0.80, 1.0, dk);

    // ---- composite (premultiplied alpha)
    vec3 outP = gC * gA + holeC * holeA * (1.0 - gA);
    float outA = gA + holeA * (1.0 - gA);
    vec3 P = clamp(body, 0.0, 1.0) * aa + outP * (1.0 - aa);
    float A = aa + outA * (1.0 - aa);
    fragColor = vec4(P, A);
}
