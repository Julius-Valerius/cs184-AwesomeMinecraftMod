#version 330 compatibility

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform sampler2D specular;

uniform vec3  shadowLightPosition;
uniform float rainStrength;
uniform int   worldTime;
uniform mat4  gbufferModelViewInverse;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 viewPos;
in vec3 viewNormal;

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 pbrData;

void main() {
    vec4 baseColor = texture(gtexture, texcoord) * glcolor;
    vec3 lightmapSample = texture(lightmap, lmcoord).rgb;

    float roughness = 0.05;
    vec3 N = normalize(viewNormal);
    vec3 V = normalize(-viewPos);
    float NdotV = max(dot(N, V), 0.001);

    float F0 = 0.04; 
    float fresnel = F0 + (1.0 - F0) * pow(1.0 - NdotV, 5.0);


    vec3 baseShaded = baseColor.rgb * lightmapSample;

    vec3 viewReflect = reflect(-V, N);
    vec3 worldReflect = normalize((gbufferModelViewInverse * vec4(viewReflect, 0.0)).xyz);

    vec3 skyColor = mix(vec3(0.05, 0.15, 0.3), vec3(0.5, 0.7, 1.0), clamp(worldReflect.y, 0.0, 1.0));
    
    vec3 result = mix(baseShaded, skyColor, fresnel);

    float baseGlassTintOpacity = 0.4; 
    float finalAlpha = mix(baseGlassTintOpacity, 1.0, baseColor.a);
    
    finalAlpha = mix(finalAlpha, 1.0, fresnel * 0.5);
    finalAlpha = clamp(finalAlpha, 0.0, 1.0);

    fragColor = vec4(result, finalAlpha);
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    pbrData = vec4(0.05, 0.0, 0.0, 1.0); 
}