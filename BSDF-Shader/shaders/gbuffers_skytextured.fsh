#version 330 compatibility

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 color = texture(gtexture, texcoord) * glcolor;
    fragColor = color;
}
