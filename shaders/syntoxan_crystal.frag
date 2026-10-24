#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEm;

out vec4 fragColor;

float synHash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
  vec2 p = FlutterFragCoord().xy / uEm * 69.0;
  vec2 g = p / 20.0;
  vec2 ic = floor(g);
  float f1 = 9.0;
  float f2 = 9.0;
  float id = 0.0;
  for (int j = -1; j < 2; j++) {
    for (int k = -1; k < 2; k++) {
      vec2 c = ic + vec2(float(k), float(j));
      float h = synHash(c);
      vec2 q = c + 0.5 + 0.4 * vec2(sin(uTime * 0.7 + h * 6.2832), cos(uTime * 0.6 + h * 5.0));
      float d = distance(g, q);
      if (d < f1) {
        f2 = f1;
        f1 = d;
        id = h;
      } else if (d < f2) {
        f2 = d;
      }
    }
  }
  float e = smoothstep(0.0, 1.0, (f2 - f1) * 9.0);
  float b = 0.45 + 0.5 * sin(id * 6.2832 + uTime * 0.8 + g.x * 0.3);
  float v = ((55.0 + 150.0 * b) * e + 18.0) / 255.0;
  fragColor = vec4(v * 0.82, v * 0.92, min(1.0, v + 0.098), 1.0);
}
