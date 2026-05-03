#version 330 compatibility

uniform sampler2D colortex0;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 c = texture(colortex0, texcoord);
    fragColor = vec4(c.rgb, 1.0);
}
