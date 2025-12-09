#include <CoreImage/CoreImage.h>

extern "C" { namespace coreimage {

    float4 thresholdFilter(sample_t image, float threshold, float targetOpacity, destination dest) {
        // Use the alpha channel to determine the shape
        float alpha = image.a;
        
        if (alpha > threshold) {
            // Protect against divide by zero
            float safeAlpha = max(alpha, 0.0001f);
            
            // Un-premultiply to get the "true" color
            float3 baseColor = image.rgb / safeAlpha;
            
            // Return fully opaque color, ignoring targetOpacity for the alpha channel
            // Core Image expects premultiplied alpha output, so if alpha is 1.0, rgb == baseColor
            return float4(baseColor, 1.0);
        } else {
            // Transparent
            return float4(0.0, 0.0, 0.0, 0.0);
        }
    }

}}
