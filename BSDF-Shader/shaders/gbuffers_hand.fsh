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
uniform mat4  gbufferModelViewInverse;

// OptiFine/Iris dynamic light values for held items (0-15).
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

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

// Evaluates Cook-Torrance diffuse + specular for one virtual block-light direction.
// Uses wrap lighting (w=0.4) for diffuse; hard clamp for specular.
vec3 blockLightLobe(vec3 Lv, vec3 N, vec3 V, float NdotV,
                    vec3 albedo, vec3 F0, float alpha, float metallic) {
    float NdotL_s = max(dot(N, Lv), 0.0);
    float NdotL_d = max((dot(N, Lv) + 0.4) / 1.4, 0.0);

    // When Lv faces away (NdotL_s == 0), V + Lv can be ~0 and normalize() returns NaN.
    // Fall back to N so H is always well-defined; spec * NdotL_s == 0 either way.
    vec3  Leff  = mix(N, Lv, step(EPSILON, NdotL_s));
    vec3  H     = normalize(V + Leff);
    float NdotH = max(dot(N, H), 0.0);
    float VdotH = max(dot(V, H), 0.0);

    vec3  F    = F_Schlick(VdotH, F0);
    float D    = D_GGX(NdotH, alpha);
    float G    = G_SmithGGX(NdotV, max(NdotL_s, EPSILON), alpha);

    vec3 spec  = (D * G * F) / (4.0 * NdotV * max(NdotL_s, EPSILON) + EPSILON);
    vec3 kDiff = (vec3(1.0) - F) * (1.0 - metallic);
    vec3 diff  = kDiff * albedo * INV_PI;

    return diff * NdotL_d + spec * NdotL_s;
}

// --- Minimal dynamic lighting MVP: up to 2 held-item point lights ---
// Implemented entirely in view space (no world light list available in a shaderpack).
// The "light position" is approximated as a small offset from the camera.
const float DYN_LIGHT_RADIUS = 8.0; // in view-space units (~blocks)
const vec3  DYN_LIGHT_COLOR  = vec3(1.0, 0.70, 0.40);
const vec3  DYN_LIGHT_POS_1  = vec3( 0.28, -0.28, -0.60);
const vec3  DYN_LIGHT_POS_2  = vec3(-0.28, -0.28, -0.60);

float dynAttenuation(float dist, float radius) {
    float x = dist / max(radius, EPSILON);
    // Smooth, bounded falloff with hard radius.
    float a = max(1.0 - x * x, 0.0);
    return a * a;
}

vec3 heldPointLight(int heldValue, vec3 lightPosVS,
                    vec3 N, vec3 V, float NdotV,
                    vec3 albedo, vec3 F0, float alpha, float metallic) {
    if (heldValue <= 0) return vec3(0.0);

    vec3  Lvec = lightPosVS - viewPos;
    float dist = length(Lvec);
    if (dist >= DYN_LIGHT_RADIUS) return vec3(0.0);

    vec3 Lv = Lvec / max(dist, EPSILON);

    float b = clamp(float(heldValue) / 15.0, 0.0, 1.0);
    float radiance = b * b * 4.0;
    float atten = dynAttenuation(dist, DYN_LIGHT_RADIUS);

    vec3 brdf = blockLightLobe(Lv, N, V, NdotV, albedo, F0, alpha, metallic);
    return brdf * DYN_LIGHT_COLOR * (radiance * atten);
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
        // LabPBR 1.3: R = perceptual smoothness, G = F0 (0-229 dielectric, 230-255 metal)
        float smoothness = specData.r;
        roughness = pow(1.0 - smoothness, 2.0);

        float gRaw = specData.g * 255.0;
        if (gRaw > 229.5) {
            metallic = 1.0;
            F0 = albedo;
        } else if (gRaw > 0.5) {
            // G channel 0-229 maps to F0 range 0-0.08 (most dielectrics top out at ~8%)
            F0 = vec3(gRaw / 229.0 * 0.08);
        }

        float alphaRaw = specData.a * 255.0;
        if (alphaRaw < 254.5) {
            emission = alphaRaw / 254.0;
        }
    }
    
    // Clamp sun roughness for forward shading — below minimum, grazing GGX blows up on blocks.
    roughness = max(roughness, 0.2);
    float alpha = roughness * roughness;

    // Tighter reflection roughness in GBUFFER so composite SSR/env sees sharp metals (armor/weapons).
    float reflRoughGbuf = roughness;
    if (metallic > 0.42) {
        float t = clamp((metallic - 0.42) / 0.58, 0.0, 1.0);
        /* Lower stored roughness → sharper SSR/env on composite (armor metals). */
        reflRoughGbuf = mix(reflRoughGbuf, min(reflRoughGbuf, 0.054 + (1.0 - metallic) * 0.028), t);
        reflRoughGbuf = max(reflRoughGbuf, 0.028);
    }

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
    specularBRDF *= 1.0 + metallic * 0.6;
    vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);
    vec3 diffuseBRDF = kD * albedo * 0.31830988618;

    vec3 lightmapColor = texture(lightmap, lmcoord).rgb;
    float skyLight   = lmcoord.y;

    vec3 lightColor = vec3(1.0, 0.95, 0.9);

    vec3 direct  = (diffuseBRDF + specularBRDF) * lightColor * NdotL * skyLight;

    // Block Light: primary upward BRDF + ambient fill
    // Single world-up direction simulates floor torches (the most common placement)
    // and creates a clear directional response (top faces bright, side/bottom faces dim).
    // An ambient fill term covers surfaces not facing the primary direction.
    float blockLight  = lmcoord.x;
    vec3  torchColor  = vec3(1.0, 0.70, 0.40);
    float blockRadiance = pow(blockLight, 2.0) * 4.0;

    mat3 worldToView = transpose(mat3(gbufferModelViewInverse));
    vec3 vL_up = normalize(worldToView * vec3(0.0, 1.0, 0.0));

    // Softer roughness floor for block-light specular: broad enough to be visible
    // across a range of viewing angles rather than a near-invisible spike.
    float blockAlpha = max(alpha, 0.45 * 0.45);

    // Diffuse
    float NdotL_block = max(dot(N, vL_up), 0.0);
    float NdotL_wrap  = max((dot(N, vL_up) + 0.4) / 1.4, 0.0);
    vec3  F_approx    = F_Schlick(NdotV, F0);
    vec3  kD_block    = (vec3(1.0) - F_approx) * (1.0 - metallic);
    vec3  blockDiff   = kD_block * albedo * INV_PI * NdotL_wrap;

    // Ambient fill for back-facing surfaces
    vec3 blockFill = kD_block * albedo * 0.28 * (1.0 - NdotL_wrap);

    // Specular
    // Scaled 15× relative to diffuse so the highlight is clearly visible as a
    // distinct warm spot on any surface facing the virtual upward light.
    vec3 blockSpec = vec3(0.0);
    if (NdotL_block > EPSILON) {
        vec3  Hb     = normalize(V + vL_up);
        float NdotHb = max(dot(N, Hb), 0.0);
        float VdotHb = max(dot(V, Hb), 0.0);
        vec3  Fb     = F_Schlick(VdotHb, F0);
        float Db     = D_GGX(NdotHb, blockAlpha);
        float Gb     = G_SmithGGX(NdotV, NdotL_block, blockAlpha);
        blockSpec    = (Db * Gb * Fb) / (4.0 * NdotV * NdotL_block + EPSILON) * NdotL_block * (1.0 + metallic * 0.65);
    }

    vec3 torch = (blockDiff + blockSpec * 15.0 + blockFill) * torchColor * blockRadiance;

    // Held-item dynamic lights (2 max; additive, doesn't replace vanilla lighting).
    float dynAlpha = max(alpha, 0.45 * 0.45);
    vec3 dynHeld =
        heldPointLight(heldBlockLightValue,  DYN_LIGHT_POS_1, N, V, NdotV, albedo, F0, dynAlpha, metallic) +
        heldPointLight(heldBlockLightValue2, DYN_LIGHT_POS_2, N, V, NdotV, albedo, F0, dynAlpha, metallic);

    dynHeld *= 1.0 + metallic * 0.35;

    vec3 ambient  = albedo * lightmapColor * 0.5;
    vec3 emissive = albedo * emission * 3.0;

    vec3 result = direct + torch + dynHeld + ambient + emissive;

    fragColor  = vec4(result, color.a);
    normalData = vec4(N * 0.5 + 0.5, 1.0);
    // .r == reflection/G-buffer roughness (can be sharper than forward roughness when metallic).
    pbrData    = vec4(reflRoughGbuf, metallic, 0.0, 1.0);
}