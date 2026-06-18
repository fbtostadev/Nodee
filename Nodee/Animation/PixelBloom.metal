//
//  PixelBloom.metal
//  Nodee
//
//  The glowing bloom behind the pixel loader, drawn as ONE analytic pass instead
//  of a stack of translucent `.shadow()` layers. It reproduces the *same* recipe
//  the old `ShadowStack` used — a sum of concentric lobes whose blur grows by
//  `× spread` and whose alpha shrinks by `÷ spread` per layer — but accumulates
//  the whole field in float and quantises it exactly once, with a fine value-noise
//  dither. That keeps the graduated falloff (hot tight core easing into a soft wide
//  halo) while dropping the grain the old stack produced on black (each translucent
//  shadow quantised to 8-bit and summed, so the noise added ~√layers) and the
//  per-frame cost (one draw vs. `layers` blur passes per cell).
//
//  Applied as a SwiftUI `colorEffect`, so the signature is
//      half4 fn(float2 position, half4 currentColor, <args…>)
//  and the returned colour is premultiplied. `intensity` is the per-cell lit
//  amount (0…1, eased on the Swift side); `count` is supplied automatically by
//  SwiftUI right after a `.floatArray` argument.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]]
half4 pixelBloom(float2 pos,
                 half4 currentColor,
                 float2 origin,       // centre of cell (0,0), in the view's points
                 float pitch,         // centre-to-centre spacing between cells
                 float dim,           // cells per side
                 float sigma0,        // gaussian σ of the innermost (tightest) lobe
                 float growth,        // per-lobe σ growth (= spread); α shrinks by it
                 float layers,        // number of lobes
                 float peak,          // alpha of the innermost lobe
                 half4 glow,          // glow colour (straight alpha; .rgb is used)
                 float dither,        // dither amplitude (~1.5/255)
                 device const float *intensity,
                 int count)
{
    int n = int(dim + 0.5);
    int L = int(layers + 0.5);

    float a = 0.0;
    for (int idx = 0; idx < count; idx++) {
        float v = intensity[idx];
        if (v <= 0.001) { continue; }                       // dark cell: no contribution
        float2 ctr = origin + float2(float(idx % n), float(idx / n)) * pitch;
        float2 dxy = pos - ctr;
        float d2 = dot(dxy, dxy);

        // Sum the concentric lobes — the smooth equivalent of the stacked shadows.
        float sigma = sigma0;
        float alpha = peak;
        for (int i = 0; i < L; i++) {
            a += v * alpha * exp(-0.5 * d2 / (sigma * sigma));
            sigma *= growth;
            alpha /= growth;
        }
    }

    // Fine value-noise dither: ±half a step is enough to dissolve the concentric
    // banding a smooth low-alpha gradient shows on a near-black field.
    float h = fract(sin(dot(pos, float2(12.9898, 78.233))) * 43758.5453);
    a = clamp(a + (h - 0.5) * dither, 0.0, 1.0);

    half av = half(a);
    return half4(glow.rgb * av, av);                        // premultiplied
}
