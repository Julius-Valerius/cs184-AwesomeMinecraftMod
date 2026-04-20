#version 330 compatibility

uniform sampler2D colortex0;  // scene color from gbuffers

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;

    // Phase 2: IBL, screen-space reflections, fog, etc. will go here

    fragColor = vec4(color, 1.0);
}
