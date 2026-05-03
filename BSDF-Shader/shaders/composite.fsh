#version 330 compatibility

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

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

// --- Minimal "ray tracing" MVP: screen-space ray-marched AO (SSAO) ---
// Casts a few short rays in view space using the depth buffer as scene geometry.
// This is true ray marching in screen space (no BVH / no world light list required).
const int   AO_RAYS  = 4;
const int   AO_STEPS = 8;
const float AO_RADIUS = 1.25;   // view-space units
const float AO_STRENGTH = 0.55; // 0..1

vec3 orthonormal(vec3 n) {
    // Pick a helper vector that isn't parallel to n
    return normalize(abs(n.z) < 0.999 ? cross(n, vec3(0.0, 0.0, 1.0)) : cross(n, vec3(0.0, 1.0, 0.0)));
}

float screenSpaceAO(vec3 viewPos, vec3 viewNormal) {
    vec3 N = normalize(viewNormal);
    vec3 T = orthonormal(N);
    vec3 B = normalize(cross(N, T));

    float noise = interleavedGradientNoise(gl_FragCoord.xy);
    float occl = 0.0;

    for (int r = 0; r < AO_RAYS; r++) {
        // Deterministic pseudo-random per-ray rotation
        float a = 6.2831853 * fract(noise + float(r) * 0.6180339);
        float u = fract(noise + float(r) * 0.3819660);

        // Cosine-ish hemisphere sample (very cheap)
        float phi = a;
        float cosTheta = sqrt(1.0 - u);
        float sinTheta = sqrt(u);
        vec3 dirTBN = vec3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
        vec3 dirVS = normalize(T * dirTBN.x + B * dirTBN.y + N * dirTBN.z);

        float stepLen = AO_RADIUS / float(AO_STEPS);
        vec3 p = viewPos + N * 0.02; // small bias to avoid self-hit

        for (int i = 0; i < AO_STEPS; i++) {
            p += dirVS * stepLen;

            vec2 uv = viewToScreen(p);
            if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0))))
                break;

            float d = texture(depthtex0, uv).r;
            if (d > 0.9999) continue;

            vec3 sceneP = getViewPos(uv);

            // If the marched point is behind the reconstructed surface point, we hit/occluded.
            // (View space is typically negative Z forward; this test works empirically for this pipeline.)
            float behind = step(p.z, sceneP.z - 0.02);
            occl += behind;
            if (behind > 0.5) break;
        }
    }

    float occN = occl / float(AO_RAYS);
    // Convert to visibility (1 = no occlusion)
    return clamp(1.0 - occN * AO_STRENGTH, 0.0, 1.0);
}

vec4 screenSpaceReflection(vec3 viewPos, vec3 viewNormal) {
    vec3 V = normalize(-viewPos);
    vec3 reflectDir = normalize(reflect(-V, viewNormal));
    
    if (reflectDir.z > 0.0) return vec4(0.0);
    
    // --- 核心修复：使用原生的 gl_FragCoord.xy 生成噪声，彻底消除条纹/摩尔纹，且零报错风险！ ---
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
            // Binary search refinement
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

        vec3 vPos = getViewPos(texcoord);

        // Screen-space ray traced AO (very cheap).
        float ao = screenSpaceAO(vPos, vNormal);
        color *= ao;

        if (roughness < 0.5) {
            vec4 ssr = screenSpaceReflection(vPos, vNormal);
            
            if (ssr.a > 0.0) {
                float cosTheta = max(dot(normalize(vNormal), normalize(-vPos)), 0.0);
                float F = 0.04 + 0.96 * pow(1.0 - cosTheta, 5.0);
                F *= (1.0 - roughness * roughness);
                color = mix(color, ssr.rgb, F * ssr.a);
            }
        }
    }
    fragColor = vec4(color, 1.0);
}