#version 330 compatibility

attribute vec4 at_tangent;

// === Outputs to fragment shader ===
out vec2 texcoord;       // base texture coordinates
out vec2 lmcoord;        // lightmap coordinates (sky + block light)
out vec4 glcolor;        // vertex color (biome tint, AO, etc.)
out vec3 viewPos;        // fragment position in view space
out vec3 normal;         // surface normal in view space
out vec3 vTangent;       // view-space tangent (Iris) for *_n normal mapping

void main() {
    // Standard vertex transform
    gl_Position = ftransform();

    // Pass texture coordinates
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

    // Vertex color (contains biome coloring and vanilla AO)
    glcolor = gl_Color;

    // View-space position for lighting calculations
    viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;

    // View-space normal + tangent (bitangent reconstructed in fragment shader)
    normal = normalize(gl_NormalMatrix * gl_Normal);
    vTangent = gl_NormalMatrix * at_tangent.xyz;
}
