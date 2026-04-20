#version 330 compatibility

// ============================================================
// BSDF Shader - Terrain Fragment Shader
// Cook-Torrance BRDF + LabPBR
// ============================================================

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

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

float clampDot(vec3 a, vec3 b) {
    return max(dot(a, b), 0.0);
}

// === GGX NDF ===
float D_GGX(float NdotH, float alpha) {
    float a2 = alpha * alpha;
    float d  = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d + EPSILON);
}

// === Schlick Fresnel ===
vec3 F_Schlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// === Smith GGX Geometry ===
float G_SmithGGX(float NdotV, float NdotL, float alpha) {
    float a2 = alpha * alpha;
    float ggxV = NdotL * sqrt(NdotV * NdotV * (1.0 - a2) + a2);
    float ggxL = NdotV * sqrt(NdotL * NdotL * (1.0 - a2) + a2);
    return 0.5 / (ggxV + ggxL + EPSILON);
}

void main() {
    // --- Sample base color ---
    vec4 color = texture(gtexture, texcoord) * glcolor;
    if (color.a < 0.1) discard;

    vec3 albedo = color.rgb; // Already in sRGB, keep as-is for output consistency

    // --- Sample LabPBR specular ---
    vec4 specData = texture(specular, texcoord);

    // Decode LabPBR
    float perceptualSmoothness = specData.r;
    float roughness = pow(1.0 - perceptualSmoothness, 2.0);
    roughness = max(roughness, 0.04); // prevent singularity

    float alpha = roughness * roughness;

    // F0 / metallic
    float greenRaw = specData.g * 255.0;
    float metallic = 0.0;
    vec3  F0 = vec3(0.04); // default dielectric

    if (greenRaw > 229.5) {
        // Metal - use albedo as F0
        metallic = 1.0;
        F0 = albedo;
    } else if (greenRaw > 0.5) {
        // Dielectric with custom F0
        F0 = vec3(specData.g * (255.0 / 229.0));
    }

    // Emission
    float emission = 0.0;
    float alphaRaw = specData.a * 255.0;
    if (alphaRaw < 254.5) {
        emission = alphaRaw / 254.0;
    }

    // --- Vectors ---
    vec3 N = normalize(normal);
    vec3 V = normalize(-viewPos);
    vec3 L = normalize(shadowLightPosition);
    vec3 H = normalize(V + L);

    float NdotL = clampDot(N, L);
    float NdotV = max(dot(N, V), EPSILON);
    float NdotH = clampDot(N, H);
    float VdotH = clampDot(V, H);

    // --- Lightmap ---
    vec3 lightmapColor = texture(lightmap, lmcoord).rgb;
    float skyLight   = lmcoord.y;
    float blockLight = lmcoord.x;

    // --- Sun color with day/night ---
    float time = float(worldTime);
    // Day: 0-12000, Sunset: 12000-13000, Night: 13000-23000, Sunrise: 23000-24000
    float sunAmount = 1.0;
    if (time > 12000.0 && time < 13500.0) {
        sunAmount = 1.0 - smoothstep(12000.0, 13500.0, time);
    } else if (time >= 13500.0 && time < 22500.0) {
        sunAmount = 0.0;
    } else if (time >= 22500.0) {
        sunAmount = smoothstep(22500.0, 24000.0, time);
    }

    float weatherDim = 1.0 - 0.6 * rainStrength;
    vec3 sunColor = vec3(1.0, 0.95, 0.9) * sunAmount * weatherDim;
    vec3 moonColor = vec3(0.1, 0.12, 0.18) * (1.0 - sunAmount);
    vec3 lightColor = sunColor + moonColor;

    // === Cook-Torrance BRDF ===
    float D = D_GGX(NdotH, alpha);
    vec3  F = F_Schlick(VdotH, F0);
    float G = G_SmithGGX(NdotV, NdotL, alpha);

    // Specular: D * G already includes 1/(4*NdotV*NdotL) via height-correlated Smith
    vec3 specularBRDF = D * G * F;

    // Diffuse: energy conserving Lambertian
    vec3 kD = (1.0 - F) * (1.0 - metallic);
    vec3 diffuseBRDF = kD * albedo * INV_PI;

    // Direct lighting
    vec3 direct = (diffuseBRDF + specularBRDF) * lightColor * NdotL * skyLight;

    // --- Torch / block light ---
    vec3 torchColor = vec3(1.0, 0.7, 0.4);
    vec3 torch = albedo * torchColor * pow(blockLight, 2.5) * 0.8;

    // --- Ambient (from lightmap) ---
    vec3 ambient = albedo * lightmapColor * 0.5;

    // --- Emission ---
    vec3 emissive = albedo * emission * 3.0;

    // --- Combine ---
    vec3 result = direct + torch + ambient + emissive;

    // Ensure result isn't darker than vanilla lightmap would give
    // This prevents the PBR shader from making things worse than default
    vec3 vanillaBaseline = albedo * lightmapColor;
    result = max(result, vanillaBaseline * 0.7);

    fragColor = vec4(result, color.a);
}
