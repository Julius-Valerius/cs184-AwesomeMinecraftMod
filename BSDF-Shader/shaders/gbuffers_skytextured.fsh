#version 330 compatibility

uniform sampler2D gtexture;
in vec2 texcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 pbrData;

void main() {
    vec4 color = texture(gtexture, texcoord) * glcolor;
    fragColor = color;
    
    normalData = vec4(0.5, 1.0, 0.5, 1.0);
    pbrData = vec4(1.0, 0.0, 0.0, 1.0);
}