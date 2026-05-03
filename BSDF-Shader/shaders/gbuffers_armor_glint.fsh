#version 330 compatibility

uniform sampler2D gtexture;

uniform int   worldTime;
uniform float frameTimeCounter;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 viewPos;
in vec3 normal;

/* Single output: additive shimmer over existing colortex0; colortex1/2 unchanged. */
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

#define GLINT_MASTER_INTENSITY 0.72
#define GLINT_ANIM_SCALE       0.055
#define GLINT_FREQ             52.0
#define GLINT_NOISE_AMP        0.045
#define GLINT_NOISE_OCTAVES    2
#define GLINT_FRESNEL_POWER    2.35

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noiseSmooth(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    vec2 cp = p;
    for (int i = 0; i < GLINT_NOISE_OCTAVES; i++) {
        v += amp * noiseSmooth(cp);
        cp *= 2.1;
        amp *= 0.5;
    }
    return v;
}

mat2 rotate2(float a) {
    float s = sin(a);
    float c = cos(a);
    return mat2(c, -s, s, c);
}

vec3 rainbowSheen(float hue) {
    hue = fract(hue);
    return clamp(
        vec3(abs(hue * 6.0 - 3.0) - 1.0,
             2.0 - abs(hue * 6.0 - 2.0),
             2.0 - abs(hue * 6.0 - 4.0)),
        0.0, 1.0);
}

void main() {
    float aVert = clamp(glcolor.a, 0.0, 1.0);
    if (aVert < 1e-3) discard;

    float wt = float(worldTime % 24000);
    float t = frameTimeCounter * GLINT_ANIM_SCALE + wt * 0.00012;

    vec3 N = normalize(normal);
    vec3 V = normalize(-viewPos);
    float NdV = max(dot(N, V), 1e-3);
    float fres = pow(max(1.0 - NdV, 0.0), GLINT_FRESNEL_POWER);

    vec2 duv = texcoord + vec2(
        fbm(texcoord * 14.7 + vec2(t * 8.33, -t * 6.71)),
        fbm(texcoord * -11.9 + vec2(t * -5.2, t * 7.94))) - 0.5;
    duv *= GLINT_NOISE_AMP;
    vec2 uv = texcoord + duv;

    vec3 texRgb = texture(gtexture, uv).rgb;
    float lmx = dot(texRgb, vec3(0.299, 0.587, 0.114));
    float mx = max(max(texRgb.r, texRgb.g), texRgb.b);
    float atlasMask = mix(1.0, clamp(0.35 + mx * 0.85 + lmx * 0.45, 0.0, 1.95),
        clamp(length(texRgb) * 8.0, 0.0, 1.0));

    float shimmer = 0.0;

    shimmer += smoothstep(0.52, 0.98,
        sin(dot(rotate2(0.0)       * uv, vec2(GLINT_FREQ, GLINT_FREQ * 0.27)) + t * 31.7 + NdV * 4.7) * 0.5 + 0.5);
    shimmer += smoothstep(0.55, 0.95,
        sin(dot(rotate2(2.0943) * uv, vec2(GLINT_FREQ * 0.31, GLINT_FREQ)) - t * 27.9 + NdV * 3.9) * 0.5 + 0.5)
        * 0.92;
    shimmer += smoothstep(0.56, 0.92,
        sin(dot(rotate2(-1.0471) * uv, vec2(-GLINT_FREQ * 0.42, GLINT_FREQ * 0.71)) + t * 37.5) * 0.5 + 0.5)
        * 0.78;

    shimmer *= 1.35 / (1.95 + NdV);

    vec3 iris = rainbowSheen(0.64 + NdV * 0.42 + shimmer * 0.18 + wt * 0.00006);
    vec3 purple = vec3(0.55, 0.28, 0.95);
    vec3 cyan   = vec3(0.35, 0.85, 0.98);
    vec3 teal   = vec3(0.25, 0.55, 0.92);
    vec3 tint = mix(mix(purple, teal, smoothstep(0.0, 1.0, iris.b)), cyan, iris.g * 0.55 + NdV * 0.35);

    float lmBlock = lmcoord.x;
    float skyl = lmcoord.y;
    float sceneVis = clamp(0.38 + pow(max(skyl, 0.0), 0.45) * 0.55 + pow(max(lmBlock, 0.0), 0.9) * 0.85, 0.22, 1.55);

    vec3 contrib = tint * shimmer * atlasMask * GLINT_MASTER_INTENSITY;
    contrib *= fres;
    contrib *= glcolor.rgb;
    contrib *= sceneVis;
    contrib *= aVert;

    fragColor = vec4(contrib, 1.0);
}
