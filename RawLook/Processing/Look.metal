#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;

float wrapHue(float hue) {
    float value = fmod(hue, 360.0f);
    return value < 0 ? value + 360 : value;
}

float dec(float value) {
    return value <= 0.04045f ? value / 12.92f : pow((value + 0.055f) / 1.055f, 2.4f);
}

float enc(float value) {
    return value <= 0.0031308f ? 12.92f * value : 1.055f * pow(value, 1.0f / 2.4f) - 0.055f;
}

float3 toHSL(float3 color) {
    float high = max(color.r, max(color.g, color.b));
    float low = min(color.r, min(color.g, color.b));
    float delta = high - low;
    float lightness = (high + low) / 2;
    if (delta == 0) {
        return float3(0, 0, lightness);
    }
    float hue = high == color.r ? (color.g - color.b) / delta
        : high == color.g ? (color.b - color.r) / delta + 2
        : (color.r - color.g) / delta + 4;
    return float3(wrapHue(hue * 60), delta / (1 - abs(2 * lightness - 1)), lightness);
}

float3 toRGB(float3 hsl) {
    float hue = wrapHue(hsl.x) / 60;
    float chroma = (1 - abs(2 * hsl.z - 1)) * hsl.y;
    float x = chroma * (1 - abs(fmod(hue, 2.0f) - 1));
    float offset = hsl.z - chroma / 2;
    float3 value = hue < 1 ? float3(chroma, x, 0)
        : hue < 2 ? float3(x, chroma, 0)
        : hue < 3 ? float3(0, chroma, x)
        : hue < 4 ? float3(0, x, chroma)
        : hue < 5 ? float3(x, 0, chroma)
        : float3(chroma, 0, x);
    return value + offset;
}

float curve(float x, thread float4 *points, int count) {
    float4 a = points[0];
    if (x <= a.x) {
        return a.y;
    }
    for (int i = 1; i < count; i++) {
        float4 b = points[i];
        if (x <= b.x) {
            return a.y + ((x - a.x) / (b.x - a.x)) * (b.y - a.y);
        }
        a = b;
    }
    return a.y;
}

/// Interpolate circular hue sectors using the original HSL hue and neutral protection.
float3 sectorColor(float3 color, thread float4 *anchors, int count) {
    float3 hsl = toHSL(color);
    float4 a = anchors[count - 1];
    float4 b = anchors[0];
    float hue = hsl.x;
    float left = a.x;
    float right = b.x + 360;
    if (hue < b.x) {
        hue += 360;
    }
    for (int i = 1; i < count; i++) {
        float4 u = anchors[i - 1];
        float4 v = anchors[i];
        if (hue >= u.x && hue < v.x) {
            a = u;
            b = v;
            left = u.x;
            right = v.x;
            break;
        }
    }
    float3 parameters = a.yzw + ((hue - left) / (right - left)) * (b.yzw - a.yzw);
    float t = clamp((hsl.y - 0.03f) / 0.15f, 0.0f, 1.0f);
    float weight = t * t * (3 - 2 * t);
    float delta = weight * parameters.z;
    hsl.x = wrapHue(hsl.x + weight * parameters.x);
    hsl.y = clamp(hsl.y * (1 + weight * (parameters.y - 1)), 0.0f, 1.0f);
    hsl.z = clamp(hsl.z + delta * (delta >= 0 ? 1 - hsl.z : hsl.z), 0.0f, 1.0f);
    return toRGB(hsl);
}

/// RAW highlight shoulder (RawTone.shoulder in LookCore): identity below `start`, then an
/// exponential roll-off with slope 1 at `start` that approaches 1.0. Applied to the linear,
/// DR-compensated CIRAWFilter output so pushed highlights roll off instead of clipping.
float shoulder(float x, float start) {
    if (x <= start) {
        return x;
    }
    float range = 1 - start;
    return start + range * (1 - exp(-(x - start) / range));
}

extern "C" {
namespace coreimage {

float4 rawLook(coreimage::sampler src, coreimage::sampler table,
               float4 counts, float4 flags, float4 options, coreimage::destination dest) {
    float4 pixel = src.sample(src.transform(dest.coord()));
    float4 anchors[16];
    float4 master[16];
    float4 red[16];
    float4 green[16];
    float4 blue[16];
    // The table is an 80x1 image (LookTable): five logical rows of 16 entries laid out side
    // by side. Read pixel centres with nearest sampling and no colour matching. A single
    // pixel row avoids Core Image's bottom-left-origin row flip.
    for (int i = 0; i < 16; i++) {
        anchors[i] = table.sample(table.transform(float2(i + 0.5, 0.5)));
        master[i] = table.sample(table.transform(float2(16 + i + 0.5, 0.5)));
        red[i] = table.sample(table.transform(float2(32 + i + 0.5, 0.5)));
        green[i] = table.sample(table.transform(float2(48 + i + 0.5, 0.5)));
        blue[i] = table.sample(table.transform(float2(64 + i + 0.5, 0.5)));
    }
    // Core Image uses premultiplied linear color; LookMath operates on straight sRGB.
    float3 linear = pixel.a > 0 ? pixel.rgb / pixel.a : float3(0);
    float3 original = clamp(float3(enc(linear.r), enc(linear.g), enc(linear.b)), 0.0f, 1.0f);
    float3 color = original;
    if (flags.x > 0) {
        color = sectorColor(color, anchors, int(options.x));
    }
    if (flags.y > 0) {
        color = float3(curve(color.r, master, int(counts.x)),
                       curve(color.g, master, int(counts.x)),
                       curve(color.b, master, int(counts.x)));
    }
    if (flags.z > 0) {
        color = float3(curve(color.r, red, int(counts.y)),
                       curve(color.g, green, int(counts.z)),
                       curve(color.b, blue, int(counts.w)));
    }
    if (flags.w > 0) {
        float3 hsl = toHSL(color);
        hsl.y = clamp(hsl.y * options.y, 0.0f, 1.0f);
        color = toRGB(hsl);
    }
    if (options.w > 0) {
        float strength = clamp(options.z, 0.0f, 1.0f);
        color = float3(enc(dec(original.r) * (1 - strength) + dec(color.r) * strength),
                       enc(dec(original.g) * (1 - strength) + dec(color.g) * strength),
                       enc(dec(original.b) * (1 - strength) + dec(color.b) * strength));
    }
    color = clamp(color, 0.0f, 1.0f);
    return float4(float3(dec(color.r), dec(color.g), dec(color.b)) * pixel.a, pixel.a);
}

float4 rawShoulder(coreimage::sample_t s, float start) {
    float3 c = s.a > 0 ? s.rgb / s.a : float3(0);
    c = float3(shoulder(c.r, start), shoulder(c.g, start), shoulder(c.b, start));
    return float4(c * s.a, s.a);
}

} // namespace coreimage
} // extern "C"
