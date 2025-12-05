#include <CoreImage/CoreImage.h>

extern "C" { namespace coreimage {

    float4 thresholdFilter(sample_t image, float threshold, float targetOpacity) {
        // Use the alpha channel to determine the shape
        float alpha = image.a;
        
        if (alpha > threshold) {
            // Protect against divide by zero
            float safeAlpha = max(alpha, 0.0001);
            
            // Un-premultiply to get the "true" color
            float3 color = image.rgb / safeAlpha;
            
            // Return the color with the requested opacity
            // Core Image expects premultiplied alpha output
            return float4(color * targetOpacity, targetOpacity);
        } else {
            // Transparent
            return float4(0.0, 0.0, 0.0, 0.0);
        }
    }

}}
