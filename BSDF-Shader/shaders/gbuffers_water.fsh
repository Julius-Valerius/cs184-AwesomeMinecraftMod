#version 330 compatibility

// ============================================================
// BSDF Shader - Water & Glass
// Preserve original colors + additive Fresnel reflections
// ============================================================

uniform sampler2D gtexture;
uniform sampler2D lightmap;

uniform vec3  shadowLightPosition;
uniform float rainStrength;
uniform int   worldTime;
uniform mat4  gbufferModelViewInverse;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 viewPos;
in vec3 viewNormal;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 baseColor = texture(gtexture, texcoord) * glcolor;
    vec3 lightmapSample = texture(lightmap, lmcoord).rgb;

    vec3 N = normalize(viewNormal);
    vec3 V = normalize(-viewPos);
    vec3 L = normalize(shadowLightPosition);
    float NdotV = max(dot(N, V), 0.001);

    // --- Day/night ---
    float time = float(worldTime);
    float sunAmount = 1.0;
    if (time > 12000.0 && time < 13500.0)
        sunAmount = 1.0 - smoothstep(12000.0, 13500.0, time);
    else if (time >= 13500.0 && time < 22500.0)
        sunAmount = 0.0;
    else if (time >= 22500.0)
        sunAmount = smoothstep(22500.0, 24000.0, time);
    float weatherDim = 1.0 - 0.5 * rainStrength;

    // --- Sky reflection color ---
    vec3 reflectDir = reflect(-V, N);
    vec3 wR = normalize((gbufferModelViewInverse * vec4(reflectDir, 0.0)).xyz);
    float up = clamp(wR.y, -0.3, 1.0);

    vec3 daySky = (up > 0.0)
        ? mix(vec3(0.5, 0.65, 0.9), vec3(0.12, 0.28, 0.75), up)
        : mix(vec3(0.5, 0.65, 0.9), vec3(0.3, 0.35, 0.4), clamp(-up * 5.0, 0.0, 1.0));
    vec3 nightSky = vec3(0.01, 0.015, 0.04);
    vec3 skyColor = mix(nightSky, daySky, sunAmount) * weatherDim;

    // Sunset tint
    float sunset = 0.0;
    if (time > 11500.0 && time < 13500.0) sunset = max(0.0, 1.0 - abs(time - 12500.0) / 1000.0);
    else if (time > 22500.0) sunset = max(0.0, 1.0 - abs(time - 23250.0) / 750.0);
    skyColor = mix(skyColor, vec3(0.9, 0.4, 0.12), sunset * clamp(1.0 - abs(up), 0.0, 1.0));

    // --- Fresnel ---
    // F0 = 0.04 for all glass/water (standard dielectric)
    float fresnel = 0.04 + 0.96 * pow(1.0 - NdotV, 5.0);

    // --- Sun specular ---
    vec3 H = normalize(V + L);
    float NdotH = max(dot(N, H), 0.0);
    float sunSpec = pow(NdotH, 2048.0) * 8.0 * sunAmount * weatherDim;

    // --- Block light for warm reflections ---
    float blockLight = lmcoord.x;
    vec3 warmLight = vec3(1.0, 0.7, 0.35) * pow(blockLight, 2.0) * 1.5;

    // === Base shading (original color, untouched) ===
    vec3 baseShaded = baseColor.rgb * lightmapSample;

    // === Reflection layer ===
    vec3 reflection = skyColor + warmLight;

    // === Blend: Fresnel controls how much reflection replaces base ===
    vec3 result = mix(baseShaded, reflection, fresnel);

    // === Add sun highlight on top (additive) ===
    result += vec3(1.0, 0.97, 0.9) * sunSpec * lmcoord.y;

    // === Alpha: more opaque at glancing angles ===
    float alpha = baseColor.a;
    alpha = max(alpha, fresnel * 0.7);

    fragColor = vec4(result, alpha);
}
