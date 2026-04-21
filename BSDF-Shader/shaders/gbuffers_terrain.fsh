#version 330 compatibility

const float PI      = 3.14159265359;
const float INV_PI  = 0.31830988618;
const float EPSILON = 1e-4;

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
uniform sampler2D lightmap;

uniform vec3  shadowLightPosition;
uniform float rainStrength;
uniform int   worldTime;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 viewPos;
in vec3 normal;

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 pbrData;

float clampDot(vec3 a, vec3 b) { return max(dot(a, b), 0.0); }

float D_GGX(float NdotH, float alpha) {
    float a2 = alpha * alpha;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d + EPSILON);
}

vec3 F_Schlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float G_SmithGGX(float NdotV, float NdotL, float alpha) {
    float a2  = alpha * alpha;
    float ggxV = NdotL * sqrt(NdotV * NdotV * (1.0 - a2) + a2);
    float ggxL = NdotV * sqrt(NdotL * NdotL * (1.0 - a2) + a2);
    return 0.5 / (ggxV + ggxL + EPSILON);
}

void main() {
    vec4 color = texture(gtexture, texcoord) * glcolor;
    if (color.a < 0.1) discard;
    vec3 albedo = color.rgb;

    vec4 specData = texture(specular, texcoord);
    float roughness = 0.8;
    float metallic = 0.0;
    vec3 F0 = vec3(0.04);
    float emission = 0.0;

    if (length(specData.rgb) > 0.001) {
        roughness = specData.g;
        
        float redRaw = specData.r * 255.0;
        if (redRaw > 229.5) {
            metallic = 1.0;
            F0 = albedo;
        } else if (redRaw > 0.5) {
            F0 = vec3(specData.r * (255.0 / 229.0));
        }
        
        float alphaRaw = specData.a * 255.0;
        if (alphaRaw < 254.5) {
            emission = alphaRaw / 254.0;
        }
    }
    
    roughness = max(roughness, 0.04);
    float alpha = roughness * roughness;

    vec3 N = normalize(normal);
    vec3 V = normalize(-viewPos);
    vec3 L = normalize(shadowLightPosition);
    vec3 H = normalize(V + L);

    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0001);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);

    float D = D_GGX(NdotH, alpha);
    vec3  F = F_Schlick(VdotH, F0);
    float G = G_SmithGGX(NdotV, NdotL, alpha);

    vec3 specularBRDF = (D * G * F) / (4.0 * NdotV * NdotL + 0.0001);
    vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
    vec3 diffuseBRDF = kD * albedo * 0.31830988618;

    vec3 lightmapColor = texture(lightmap, lmcoord).rgb;
    float skyLight   = lmcoord.y;
    float blockLight = lmcoord.x;

    vec3 lightColor = vec3(1.0, 0.95, 0.9); 

    vec3 direct  = (diffuseBRDF + specularBRDF) * lightColor * NdotL * skyLight;
    vec3 torch   = albedo * vec3(1.0, 0.7, 0.4) * pow(blockLight, 2.5) * 0.8;
    vec3 ambient = albedo * lightmapColor * 0.5;
    vec3 emissive = albedo * emission * 3.0;

    vec3 result = direct + torch + ambient + emissive;

    fragColor  = vec4(result, color.a);
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    pbrData    = vec4(roughness, metallic, 0.0, 1.0);
}