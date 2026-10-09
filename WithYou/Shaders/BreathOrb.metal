//
//  BreathOrb.metal
//  WithYou
//
//  The Refocus orb: a soft ball of light that grows with the breath and slowly changes
//  shape. Applied with SwiftUI's colorEffect (see BreathOrbView.swift). Kept cheap: a few
//  low-frequency waves, no textures, no loops.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// - position: this pixel, in points from the view's top-left corner.
/// - color: the view's own color here (a plain filled shape); only its coverage is used.
/// - size: the view's size in points.
/// - time: seconds of motion so far; drives the slow change of shape.
/// - level: how full the breath is, 0 (empty) to 1 (full).
/// - accent: the app accent for the current light/dark appearance (premultiplied).
/// Returns a premultiplied color; fully transparent outside the orb and its glow.
[[ stitchable ]] half4 breathOrb(float2 position, half4 color, float2 size, float time, float level, half4 accent) {
    float side = max(min(size.x, size.y), 1.0);
    // -1...1 across the shorter side, centered.
    float2 uv = (position - size * 0.5) / (side * 0.5);
    float r = length(uv);
    float angle = atan2(uv.y, uv.x);
    float breath = clamp(level, 0.0, 1.0);

    // The orb grows with the breath and leaves room around it for the glow.
    float radius = mix(0.52, 0.74, breath);

    // Soft, organic edge: three slow waves around the rim. Whole-number frequencies
    // keep the edge seamless all the way around.
    float wobble = 0.030 * sin(3.0 * angle + time * 0.55)
                 + 0.018 * sin(5.0 * angle - time * 0.80 + 1.3)
                 + 0.012 * sin(2.0 * angle + time * 1.05 + 2.6);
    float edge = radius * (1.0 + wobble);

    // 1 inside, 0 outside, with a feathered rim.
    float body = 1.0 - smoothstep(edge - 0.07, edge + 0.012, r);

    // Inner light from the upper left, a little brighter on a full breath.
    float2 lightCenter = float2(-0.30, -0.38) * radius;
    float lightDistance = length(uv - lightCenter) / max(radius, 0.001);
    float shimmer = 0.035 * sin(uv.x * 2.7 + time * 0.45) * sin(uv.y * 2.3 - time * 0.35);
    float innerLight = clamp(exp(-lightDistance * lightDistance * 3.2) * (0.20 + 0.16 * breath) + shimmer, 0.0, 1.0);
    // Most solid near the light, softer toward the far rim.
    float bodyAlpha = body * mix(0.94, 0.46, smoothstep(0.0, 1.7, lightDistance));

    // A gentle glow around the rim that fades to nothing before the view's edges.
    float outside = max(r - edge, 0.0);
    float glow = exp(-outside * 7.0) * (0.16 + 0.20 * breath) * (1.0 - body);
    glow *= 1.0 - smoothstep(0.82, 1.0, r);

    half3 accentRGB = accent.a > 0.001h ? accent.rgb / accent.a : half3(0.0h);
    half3 bodyRGB = mix(accentRGB, half3(1.0h), half3(half(innerLight)));

    half alpha = half(clamp(bodyAlpha + glow, 0.0, 1.0));
    half3 rgb = bodyRGB * half(bodyAlpha) + accentRGB * half(glow);
    rgb = min(rgb, half3(alpha));

    half coverage = color.a;
    return half4(rgb * coverage, alpha * coverage);
}
