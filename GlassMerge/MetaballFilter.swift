import CoreImage

class MetaballFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    @objc dynamic var threshold: CGFloat = 0.5
    @objc dynamic var blurRadius: CGFloat = 10.0
    @objc dynamic var opacity: CGFloat = 0.5 // Default opacity for glass effect
    
    // Use string-based initialization to ensure compatibility
    private let blurFilter = CIFilter(name: "CIGaussianBlur")!
    
    // Note: CIColorKernel(source:) is deprecated in favor of Metal-based kernels.
    // However, using Metal kernels requires adding .metal files and configuring build rules,
    // which is outside the scope of this code-only modification.
    // This deprecated initializer still functions correctly on current iOS versions.
    private static let thresholdKernel = CIColorKernel(source: """
        kernel vec4 thresholdFilter(__sample image, float threshold, float targetOpacity) {
            // Use the alpha channel to determine the shape
            float alpha = image.a;
            
            if (alpha > threshold) {
                // Let's try un-premultiplying to get the "true" color back at the edges.
                // Protect against divide by zero.
                float safeAlpha = max(alpha, 0.0001);
                vec3 color = image.rgb / safeAlpha;
                
                // Return the color with the requested opacity
                // We need to multiply the color by the opacity if we are outputting premultiplied alpha,
                // but usually CIColorKernel outputs are expected to be premultiplied.
                // Core Image typically works with premultiplied alpha.
                
                return vec4(color * targetOpacity, targetOpacity);
            } else {
                // Transparent
                return vec4(0.0, 0.0, 0.0, 0.0);
            }
        }
    """)!
    
    override var outputImage: CIImage? {
        guard let inputImage = self.inputImage else { return nil }
        
        // 1. Apply Gaussian Blur
        blurFilter.setValue(inputImage, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        
        guard let blurredImage = blurFilter.outputImage else { return nil }
        
        // 2. Apply Threshold Kernel
        // We need to pass the blurred image, the threshold value, and the target opacity
        return MetaballFilter.thresholdKernel.apply(
            extent: blurredImage.extent,
            arguments: [blurredImage, Float(threshold), Float(opacity)]
        )
    }
}
