#version 330 compatibility

uniform int renderStage;

in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = glcolor;
}
