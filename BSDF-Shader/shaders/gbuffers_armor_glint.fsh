#version 330 compatibility

uniform sampler2D gtexture;

uniform int   worldTime;
uniform float frameTimeCounter;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 viewPos;
in vec3 normal;

/* Single RT: premulti-style blend SRC_ALPHA ONE adds src.rgb * src.a without touching dst alpha. */
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 fragColor;

#define GLINT_MAX_ADD      0.42
#define GLINT_SPEED        0.042
#define GLINT_FREQ_BIAS    1.08
#define GLINT_NOISE_AMP    0.028
#define GLINT_OCTAVES      3
#define GLINT_FRES_POW     2.05
#define GLINT_FRES_FLOOR   0.07
#define GLINT_SPARKLE_STR  0.22

const float GOLDEN = 0.61803398875;

float hash21(vec2 p) {
    return fract(sin(dot(p + vec2(13.71, 9.183), vec2(127.1, 311.7))) * 43758.5453123);
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
    for (int i = 0; i < GLINT_OCTAVES; i++) {
        v += amp * noiseSmooth(cp);
        cp *= 2.08;
        amp *= 0.5;
    }
    return v;
}

mat2 rot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, -s, s, c);
}

/* Smooth band 0..1 from phase in radians */
float shimmerBand(vec2 pq, float ang, float k, float scroll) {
    vec2 uv = rot(ang) * pq;
    float ph = uv.x * k + uv.y * k * (0.18 + GOLDEN * 0.2) + scroll;
    float s = sin(ph) * 0.5 + 0.5;
    s *= s * (3.0 - 2.0 * s);
    return smoothstep(0.12, 0.96, s);
}

vec3 irisPalette(float phase) {
    vec3 a = vec3(0.50, 0.35, 0.95);
    vec3 b = vec3(0.25, 0.65, 0.98);
    vec3 c = vec3(0.55, 0.92, 0.95);
    float t = fract(phase + 0.612);
    return mix(mix(a, b, smoothstep(0.0, 1.0, t)), c, smoothstep(0.25, 0.92, cos(6.28318 * (t + 0.07)) * 0.5 + 0.5));
}

void main() {
    float aVert = clamp(glcolor.a, 0.0, 1.0);
    if (aVert < 1e-4) discard;

    float wt = float(worldTime & 8191);
    float tSmooth = frameTimeCounter * GLINT_SPEED + wt * (1.0 / 24000.0);

    vec3 N = normalize(normal);
    vec3 V = normalize(-viewPos);
    float NdV = clamp(dot(N, V), 0.003, 1.0);

    float edge = pow(1.0 - NdV, GLINT_FRES_POW);
    float fresBias = GLINT_FRES_FLOOR + (1.0 - GLINT_FRES_FLOOR) * edge;

    vec2 warp = vec2(
        fbm(texcoord * 16.9 + vec2(tSmooth * 4.11, -tSmooth * 3.07)),
        fbm(texcoord * -14.4 + vec2(-tSmooth * 2.9, tSmooth * 5.52))) - 0.5;
    warp *= GLINT_NOISE_AMP;

    vec2 uvW = texcoord + warp;
    vec2 uvNW = texcoord + warp * 0.62;

    vec3 texRgb = texture(gtexture, uvW).rgb;
    vec3 texBase = texture(gtexture, uvNW * 1.013 + vec2(0.019, -0.011)).rgb;
    float mW = max(max(texRgb.r, texRgb.g), texRgb.b);
    float lW = dot(texRgb, vec3(0.299, 0.587, 0.114));
    float mN = max(max(texBase.r, texBase.g), texBase.b);
    float mask = clamp(0.38 + mix(mW * 1.05, mN * 1.05, GOLDEN * 0.5) + lW * 0.52, 0.0, 1.95);
    mask = clamp(mask + fbm(texcoord * 64.7 + tSmooth * 3.14) * 0.035, 0.0, 1.95);

    float fq = GLINT_FREQ_BIAS * mix(62.0, 86.0, fbm(texcoord * 14.12 + GOLDEN));

    float s1 = shimmerBand(uvW, 0.0, fq, +tSmooth * (28.8 + GOLDEN));
    float s2 = shimmerBand(uvW, 2.094395, fq * (0.86 + GOLDEN * 0.06), -tSmooth * 24.1);
    float s3 = shimmerBand(uvW, -1.047198, fq * 1.07, tSmooth * 33.9 + NdV * 2.17);
    float bands = clamp((s1 * 1.07 + s2 * 1.03 + s3 * 0.96) * (1.0 / 3.15), 0.0, 2.35);

    float sp = dot(rot(1.8849) * (uvW * 96.13), vec2(1.0))
        + tSmooth * 41.73 - NdV * 5.71;
    float sparks = smoothstep(0.975, 0.998, cos(sp) * 0.5 + 0.5) * GLINT_SPARKLE_STR;

    float pulse = cos(tSmooth * 6.283 * 2.71 + NdV * 4.31) * 0.5 + 0.5;

    vec3 hue = irisPalette(shimmerBand(texcoord.xy * 44.21, GOLDEN * 3.14159 * 2.09, 0.71, wt * (1.0 / 900.0))
        + tSmooth + bands * GOLDEN);

    vec3 tint = hue * bands * fresBias;

    tint = mix(hue * GOLDEN * 0.52, tint, bands);
    tint += sparks * irisPalette(sp * 6.283 + tSmooth);

    float lmBlk = lmcoord.x;
    float lmSky = lmcoord.y;
    float scene = clamp(
        mix(0.33, 0.95, pow(max(lmSky, 0.0), 0.52)) +
        pow(max(lmBlk, 0.0), 0.92) * 0.45,
        0.25, 1.25);

    vec3 glintRgb = tint * mask * scene * glcolor.rgb;
    glintRgb *= (0.78 + 0.22 * pulse);

    float strength = GLINT_MAX_ADD * aVert * clamp(bands * 0.88 + sparks * 2.1, 0.0, 1.15);
    strength = clamp(strength, 0.0, GLINT_MAX_ADD);

    if (strength < 1e-4) discard;

    fragColor = vec4(glintRgb, strength);
}
