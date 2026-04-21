#version 330 compatibility

out vec4 glcolor;
out vec3 wPos;

uniform mat4 gbufferModelViewInverse;

void main() {
    gl_Position = ftransform();
    glcolor = gl_Color;
    
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    wPos = (gbufferModelViewInverse * viewPos).xyz;
}