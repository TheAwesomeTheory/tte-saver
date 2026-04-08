#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertexPassthrough(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

// MARK: - Uniforms

struct Uniforms {
    float time;
    float2 resolution;
};

// MARK: - Texture sampling

fragment float4 textureFragment(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear);
    return tex.sample(s, in.uv);
}

// MARK: - Screen blend (compositing text over background)

fragment float4 screenBlendFragment(VertexOut in [[stage_in]],
                                     texture2d<float> base [[texture(0)]],
                                     texture2d<float> overlay [[texture(1)]]) {
    constexpr sampler s(filter::linear);
    float4 b = base.sample(s, in.uv);
    float4 o = overlay.sample(s, in.uv);
    // Screen blend: 1 - (1-base) * (1-overlay)
    float4 result = 1.0 - (1.0 - b) * (1.0 - o);
    result.a = 1.0;
    return result;
}

// MARK: - Glow effect

fragment float4 glowFragment(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              constant Uniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear);
    float4 color = tex.sample(s, in.uv);

    // Sample surrounding pixels for bloom
    float2 texelSize = 1.0 / uniforms.resolution;
    float4 bloom = float4(0);
    for (int x = -3; x <= 3; x++) {
        for (int y = -3; y <= 3; y++) {
            float2 offset = float2(x, y) * texelSize * 2.0;
            bloom += tex.sample(s, in.uv + offset);
        }
    }
    bloom /= 49.0;

    return color + bloom * 0.4;
}

// MARK: - CRT scanline effect

fragment float4 crtFragment(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             constant Uniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear);
    float4 color = tex.sample(s, in.uv);

    // Scanlines
    float scanline = sin(in.uv.y * uniforms.resolution.y * 3.14159) * 0.5 + 0.5;
    scanline = pow(scanline, 0.3);

    // Vignette
    float2 center = in.uv - 0.5;
    float vignette = 1.0 - dot(center, center) * 1.5;

    // Slight chromatic aberration
    float2 caOffset = center * 0.002;
    float r = tex.sample(s, in.uv + caOffset).r;
    float g = color.g;
    float b = tex.sample(s, in.uv - caOffset).b;

    return float4(r, g, b, 1.0) * scanline * vignette;
}

// MARK: - Plasma background

fragment float4 plasmaFragment(VertexOut in [[stage_in]],
                                constant Uniforms &uniforms [[buffer(0)]]) {
    float t = uniforms.time * 0.5;
    float2 uv = in.uv * 4.0;

    float v = sin(uv.x + t);
    v += sin((uv.y + t) * 0.5);
    v += sin((uv.x + uv.y + t) * 0.5);
    v += sin(length(uv + t) * 0.5);
    v *= 0.5;

    float3 color = float3(
        sin(v * 3.14159 + 0.0) * 0.5 + 0.5,
        sin(v * 3.14159 + 2.094) * 0.5 + 0.5,
        sin(v * 3.14159 + 4.189) * 0.5 + 0.5
    );

    return float4(color * 0.3, 1.0);  // Dim so text shows over it
}
