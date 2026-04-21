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

        if (roughness < 0.5) {
            vec3 vPos = getViewPos(texcoord);
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