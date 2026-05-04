#version 330 compatibility

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

const float IBL_DIFFUSE_STRENGTH = 0.034;
const float IBL_SPEC_MIX_CAP     = 0.38;
const float IBL_DIELECTRIC_ROUGH_MAX = 0.36;
const float CLEAR_ROUGH_THRESH   = 0.10;
const float CLEAR_METAL_THRESH   = 0.04;
const float CLEAR_REFL_MUL       = 0.28;

float interleavedGradientNoise(vec2 n) {
    return fract(52.9829189 * fract(dot(n, vec2(0.06711056, 0.00583715))));
}

vec3 getViewPos(vec2 uv) {
    float depth = texture(depthtex0, uv).r;
    vec4 ndcPos = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 viewPos = gbufferProjectionInverse * ndcPos;
    return viewPos.xyz / viewPos.w;
}

vec2 viewToScreen(vec3 vPos) {
    vec4 proj = gbufferProjection * vec4(vPos, 1.0);
    return (proj.xy / proj.w) * 0.5 + 0.5;
}

vec3 worldDirFromView(vec3 vDir) {
    return normalize((gbufferModelViewInverse * vec4(vDir, 0.0)).xyz);
}

vec3 iblDiffuseIrradiance(vec3 Nw) {
    float h = Nw.y;
    vec3 sky = mix(vec3(0.12, 0.14, 0.18), vec3(0.36, 0.48, 0.64), smoothstep(-0.12, 0.50, h));
    vec3 ground = vec3(0.16, 0.14, 0.12);
    return mix(ground, sky, smoothstep(-0.20, 0.22, h));
}

vec3 iblSpecularEnv(vec3 Rw, float roughness, float metallic) {
    float h = Rw.y;
    vec3 sky = mix(vec3(0.06, 0.08, 0.12), vec3(0.42, 0.56, 0.82), smoothstep(-0.05, 0.70, h));
    vec3 hor = vec3(0.26, 0.24, 0.22);
    sky = mix(sky, hor, (1.0 - smoothstep(-0.28, 0.50, h)) * 0.44);
    float blur = clamp(roughness * roughness * 1.2, 0.0, 1.0);
    sky = mix(sky, sky * 0.86, blur);

    vec3 Lv = shadowLightPosition;
    vec3 Lw = (dot(Lv, Lv) > 1e-8) ? worldDirFromView(normalize(Lv)) : vec3(0.2, 1.0, 0.15);
    float sunPow = mix(72.0, 260.0, (1.0 - roughness) * (0.5 + metallic * 0.5));
    float sunHit = pow(max(dot(Rw, normalize(Lw)), 0.0), sunPow);
    sky += vec3(1.0, 0.95, 0.88) * sunHit * (0.26 + metallic * 0.55);

    float groundB = smoothstep(-0.85, -0.04, -h);
    sky += vec3(0.11, 0.10, 0.09) * groundB * mix(0.22, 0.40, metallic);
    return sky;
}

const int   AO_RAYS  = 4;
const int   AO_STEPS = 8;
const float AO_RADIUS = 1.25;
const float AO_STRENGTH = 0.55;

vec3 orthonormal(vec3 n) {
    return normalize(abs(n.z) < 0.999 ? cross(n, vec3(0.0, 0.0, 1.0)) : cross(n, vec3(0.0, 1.0, 0.0)));
}

float screenSpaceAO(vec3 viewPos, vec3 viewNormal) {
    vec3 N = normalize(viewNormal);
    vec3 T = orthonormal(N);
    vec3 B = normalize(cross(N, T));

    float noise = interleavedGradientNoise(gl_FragCoord.xy);
    float occl = 0.0;

    for (int r = 0; r < AO_RAYS; r++) {
        float a = 6.2831853 * fract(noise + float(r) * 0.6180339);
        float u = fract(noise + float(r) * 0.3819660);
        float phi = a;
        float cosTheta = sqrt(1.0 - u);
        float sinTheta = sqrt(u);
        vec3 dirTBN = vec3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
        vec3 dirVS = normalize(T * dirTBN.x + B * dirTBN.y + N * dirTBN.z);

        float stepLen = AO_RADIUS / float(AO_STEPS);
        vec3 p = viewPos + N * 0.02;

        for (int i = 0; i < AO_STEPS; i++) {
            p += dirVS * stepLen;
            vec2 uv = viewToScreen(p);
            if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0))))
                break;
            float d = texture(depthtex0, uv).r;
            if (d > 0.9999) continue;
            vec3 sceneP = getViewPos(uv);
            float behind = step(p.z, sceneP.z - 0.02);
            occl += behind;
            if (behind > 0.5) break;
        }
    }
    float occN = occl / float(AO_RAYS);
    return clamp(1.0 - occN * AO_STRENGTH, 0.0, 1.0);
}

vec4 screenSpaceReflection(vec3 viewPos, vec3 viewNormal) {
    vec3 V = normalize(-viewPos);
    vec3 reflectDir = normalize(reflect(-V, viewNormal));

    if (reflectDir.z > 0.0) return vec4(0.0);

    float jitter = interleavedGradientNoise(gl_FragCoord.xy);

    vec3 currentPos = viewPos + reflectDir * (0.1 + jitter * 0.1) + viewNormal * 0.05;
    vec3 lastPos = currentPos;
    float stepSize = 0.2;

    currentPos += reflectDir * stepSize * jitter;

    for (int i = 0; i < 64; i++) {
        lastPos = currentPos;
        currentPos += reflectDir * stepSize;
        stepSize *= 1.06;

        if (currentPos.z > -0.1) return vec4(0.0);

        vec2 sampleUV = viewToScreen(currentPos);
        if (any(lessThan(sampleUV, vec2(0.0))) || any(greaterThan(sampleUV, vec2(1.0))))
            return vec4(0.0);

        float sampledDepth = texture(depthtex0, sampleUV).r;
        if (sampledDepth > 0.9999) continue;

        vec3 sampledPos = getViewPos(sampleUV);
        float diff = currentPos.z - sampledPos.z;

        if (diff < 0.0 && diff > -max(3.0, stepSize * 2.0)) {
            for (int j = 0; j < 8; j++) {
                vec3 midPos = (lastPos + currentPos) * 0.5;
                vec2 midUV = viewToScreen(midPos);
                vec3 midSampled = getViewPos(midUV);
                if (midPos.z < midSampled.z) currentPos = midPos;
                else lastPos = midPos;
            }

            vec2 finalUV = viewToScreen(currentPos);
            vec2 edgeFade = smoothstep(0.0, 0.08, finalUV) * smoothstep(1.0, 0.92, finalUV);
            float fade = edgeFade.x * edgeFade.y;

            return vec4(texture(colortex0, finalUV).rgb, fade);
        }
    }
    return vec4(0.0);
}

void main() {
    vec3 color = texture(colortex0, texcoord).rgb;
    float depth = texture(depthtex0, texcoord).r;

    if (depth < 0.9999) {
        vec3 vNormal = texture(colortex1, texcoord).xyz * 2.0 - 1.0;
        vec4 pbr = texture(colortex2, texcoord);
        float roughness = pbr.r;
        float metallic  = clamp(pbr.g, 0.0, 1.0);

        vec3 vPos = getViewPos(texcoord);

        float ao = screenSpaceAO(vPos, vNormal);
        color *= ao;

        vec3 N = normalize(vNormal);
        vec3 V = normalize(-vPos);
        float NdotV = max(dot(N, V), 0.0);

        vec3 Nw = worldDirFromView(N);
        vec3 Rw = worldDirFromView(normalize(reflect(-V, N)));

        vec3 irr = iblDiffuseIrradiance(Nw);
        color += irr * (1.0 - metallic) * IBL_DIFFUSE_STRENGTH * ao;

        vec3 specEnv = iblSpecularEnv(Rw, roughness, metallic);
        specEnv *= mix(0.70, 1.0, metallic);

        vec4 ssr = screenSpaceReflection(vPos, vNormal);
        float ssrBlend = clamp(ssr.a * (0.34 + (1.0 - roughness) * 0.26 + metallic * 0.16), 0.0, 1.0);
        float ssrRoughAtten = mix(smoothstep(0.16, 0.42, roughness), 1.0, metallic);
        ssrBlend *= 0.20 + 0.80 * ssrRoughAtten;

        vec3 refl = mix(specEnv, ssr.rgb, ssrBlend);

        vec3 F0 = mix(vec3(0.04), vec3(0.75), metallic);
        vec3 Fvec = F0 + (1.0 - F0) * pow(1.0 - NdotV, 5.0);
        float Fw = (Fvec.x + Fvec.y + Fvec.z) / 3.0;

        float gloss = clamp(1.0 - roughness, 0.0, 1.0);
        float reflWeight =
            Fw * clamp(0.035 + metallic * 0.48 + gloss * 0.18, 0.0, 0.88);
        reflWeight = min(reflWeight, IBL_SPEC_MIX_CAP);

        float clearSurf =
            step(roughness, CLEAR_ROUGH_THRESH) * step(metallic, CLEAR_METAL_THRESH);
        reflWeight *= mix(1.0, CLEAR_REFL_MUL, clearSurf);

        bool wantProbe = metallic > 0.14
            || (roughness < IBL_DIELECTRIC_ROUGH_MAX && metallic < 0.10);

        if (wantProbe) {
            color = mix(color, refl, reflWeight);
        }
    }
    fragColor = vec4(color, 1.0);
}