import CoreImage

class MetaballFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    @objc dynamic var threshold: CGFloat = 0.5
    @objc dynamic var blurRadius: CGFloat = 10.0
    
    // Use string-based initialization to ensure compatibility
    private let blurFilter = CIFilter(name: "CIGaussianBlur")!
    
    // Note: CIColorKernel(source:) is deprecated in favor of Metal-based kernels.
    // However, using Metal kernels requires adding .metal files and configuring build rules,
    // which is outside the scope of this code-only modification.
    // This deprecated initializer still functions correctly on current iOS versions.
    private static let thresholdKernel = CIColorKernel(source: """
        kernel vec4 thresholdFilter(__sample image, float threshold) {
            // Use the alpha channel to determine the shape
            float alpha = image.a;
            
            // If alpha is above threshold, output the pixel with full opacity (1.0).
            // To prevent the "feathered" edge where the blur fades out, we check strictly against the threshold.
            // We also need to unpremultiply the RGB values if the blur premultiplied them, 
            // but typically for a solid look, taking the RGB as-is (or normalized) works best if we force alpha to 1.0.
            
            if (alpha > threshold) {
                // Option 1: Return the original color, but force alpha to 1.0.
                // This might look weird if the blur mixed the color with transparent black (premultiplied).
                // A better approach for "flat" metaballs is often to just output a solid color, 
                // but we want to preserve the ball's color/texture.
                
                // Since the edge is where alpha ~ threshold, the RGB there might be faded.
                // We can boost the RGB to compensate for the fade if we assume premultiplication.
                // vec3 color = image.rgb / alpha; // Un-premultiply
                // return vec4(color, 1.0);
                
                // Let's try un-premultiplying to get the "true" color back at the edges.
                // Protect against divide by zero.
                float safeAlpha = max(alpha, 0.0001);
                vec3 color = image.rgb / safeAlpha;
                return vec4(color, 1.0);
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
        // We need to pass the blurred image and the threshold value
        return MetaballFilter.thresholdKernel.apply(
            extent: blurredImage.extent,
            arguments: [blurredImage, Float(threshold)]
        )
    }
}
