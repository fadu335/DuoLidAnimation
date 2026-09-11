#include <metal_stdlib>
using namespace metal;
struct Uniforms {
    float progress, perspective, blur, darkness;
    float compression, width, height, padding;
};
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Projective sheet, bottom edge fixed. 72 degrees matches the public site's
// maximum tilt. No extra wave/bulge: that made the first version look rubbery.
vertex VertexOut foldVertex(uint vid [[vertex_id]], constant Uniforms &u [[buffer(0)]]) {
    const uint columns = 32, rows = 48;
    const float2 corners[6] = {float2(0,0),float2(1,0),float2(0,1),float2(1,0),float2(1,1),float2(0,1)};
    uint cell = vid / 6;
    float2 grid = (float2(cell % columns, cell / columns) + corners[vid % 6]) / float2(columns, rows);
    float theta = u.progress * (72.0 * M_PI_F / 180.0);
    float w = 1.0 + u.perspective * grid.y * sin(theta);
    float h = mix(1.0, cos(theta), u.compression);
    VertexOut out;
    out.position = float4(grid.x * 2.0 - 1.0, 2.0 * grid.y * h - w, 0.0, w);
    out.uv = float2(grid.x, 1.0 - grid.y);
    return out;
}

fragment float4 foldFragment(VertexOut in [[stage_in]],
    texture2d<float> desktop [[texture(0)]], texture2d<float> blur6 [[texture(1)]],
    texture2d<float> blur16 [[texture(2)]], texture2d<float> blur36 [[texture(3)]],
    constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float p = u.progress;
    float3 color = desktop.sample(s, uv).rgb;
    if (p < 0.00001) return float4(color, 1);
    if (u.blur > 0.0) {
        float2 zoomed = (uv - 0.5) / 1.03 + 0.5;
        // Successive translucent layers reproduce depth-dependent frost.
        color = mix(color, blur6.sample(s, zoomed).rgb, p * (1.0 - smoothstep(0.30, 0.75, uv.y)));
        color = mix(color, blur16.sample(s, zoomed).rgb, p * (1.0 - smoothstep(0.15, 0.52, uv.y)));
        color = mix(color, blur36.sample(s, zoomed).rgb, p * (1.0 - smoothstep(0.06, 0.34, uv.y)));
    }
    // Corner shadows and a top-down shade: the lower half retains its brightness.
    float left = 0.55 * (1.0 - smoothstep(0.0, 0.60, length(uv / float2(1.2,0.6))));
    float right = 0.55 * (1.0 - smoothstep(0.0, 0.60, length((uv-float2(1,0)) / float2(1.2,0.6))));
    float top = 0.35 * (1.0 - smoothstep(0.0,0.45,uv.y));
    float shade = 1.0 - (1.0-left)*(1.0-right)*(1.0-top);
    color *= 1.0 - shade * p * u.darkness;

    // Feather into the black surroundings instead of exposing a sharp trapezoid.
    float feather = max(0.00001, p * 0.22);
    float y = uv.y / feather;
    float mask = y < 0.25 ? mix(0.0,0.25,y/0.25)
               : y < 0.55 ? mix(0.25,0.65,(y-0.25)/0.30)
               : mix(0.65,1.0,clamp((y-0.55)/0.45,0.0,1.0));
    float sideWidth = p * 0.014 * (1.0 - smoothstep(0.0,0.5,uv.y));
    float sideMask = sideWidth > 0.00001 ? smoothstep(0.0,sideWidth,min(uv.x,1.0-uv.x)) : 1.0;
    return float4(color * mask * sideMask, 1.0);
}
