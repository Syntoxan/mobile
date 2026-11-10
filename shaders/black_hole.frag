#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;

out vec4 fragColor;

void main()
{
    fragColor = vec4(0.0);
}
