#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float point_size [[point_size]];
    float4 color;
};

vertex VertexOut vertex_point(uint id [[vertex_id]],
                              constant float2* positions [[buffer(0)]],
                              constant float4* colors [[buffer(1)]]) {
    VertexOut out;
    out.position = float4(positions[id], 0.0, 1.0);
    out.point_size = 24.0;
    out.color = colors[id];
    return out;
}

vertex VertexOut vertex_packet(uint id [[vertex_id]],
                               constant float2* positions [[buffer(0)]],
                               constant float4* colors [[buffer(1)]]) {
    VertexOut out;
    out.position = float4(positions[id], 0.0, 1.0);
    out.point_size = 10.0;
    out.color = colors[id];
    return out;
}

fragment float4 fragment_point(VertexOut in [[stage_in]],
                               float2 pointCoord [[point_coord]]) {
    float2 coord = pointCoord * 2.0 - 1.0;
    float dist = length(coord);
    if (dist > 1.0) {
        discard_fragment();
    }
    // Smooth antialiasing edge
    float alpha = smoothstep(1.0, 0.85, dist);
    return float4(in.color.rgb, in.color.a * alpha);
}

struct LineVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex LineVertexOut vertex_line(uint id [[vertex_id]],
                                constant float2* positions [[buffer(0)]],
                                constant float4* colors [[buffer(1)]]) {
    LineVertexOut out;
    out.position = float4(positions[id], 0.0, 1.0);
    out.color = colors[id];
    return out;
}

fragment float4 fragment_line(LineVertexOut in [[stage_in]]) {
    return in.color;
}
