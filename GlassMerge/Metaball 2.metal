#include <CoreImage/CoreImage.h>

extern "C" { namespace coreimage {

    // Helper for HSV to RGB conversion
    float3 hsv2rgb(float3 c) {
        float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }

    float4 thresholdFilter(sample_t image, float threshold, float targetOpacity, float time, destination dest) {
        // Use the alpha channel to determine the shape
        float alpha = image.a;
        
        if (alpha > threshold) {
            // Protect against divide by zero
            float safeAlpha = max(alpha, 0.0001f);
            
            // Un-premultiply to get the "true" color
            float3 baseColor = image.rgb / safeAlpha;
            
            // Calculate holographic rainbow effect
            float2 coord = dest.coord();
            // Create a shifting linear gradient (diagonal)
            // Adjust scale (0.002) to control rainbow frequency (width of bands)
            float hue = dot(coord, float2(0.7, 0.7)) * 0.002 + time;
            
            // Increased saturation (0.2 -> 0.3) for better visibility
            // Kept value high for sheen
            float3 rainbow = hsv2rgb(float3(hue, 0.3, 1.0));
            
            // Blend rainbow with base color
            // Increased mix strength (0.1 -> 0.2) to make it more visible
            // while still allowing base grey scales to show through
            float3 finalColor = mix(baseColor, rainbow, 0.2);
            
            // Return fully opaque color, ignoring targetOpacity for the alpha channel
            // Core Image expects premultiplied alpha output, so if alpha is 1.0, rgb == finalColor
            return float4(finalColor, 1.0);
        } else {
            // Transparent
            return float4(0.0, 0.0, 0.0, 0.0);
        }
    }

}}
