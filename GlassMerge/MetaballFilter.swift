import CoreImage

class MetaballFilter: CIFilter {
    @objc dynamic var inputImage: CIImage?
    @objc dynamic var threshold: CGFloat = 0.5
    @objc dynamic var blurRadius: CGFloat = 10.0
    @objc dynamic var opacity: CGFloat = 0.5 // Default opacity for glass effect
    @objc dynamic var time: CGFloat = 0.0 // Time for holographic effect animation
    
    // Use string-based initialization to ensure compatibility
    private let blurFilter = CIFilter(name: "CIGaussianBlur")!
    
    // Metal-based threshold kernel
    private static let thresholdKernel: CIColorKernel = {
        do {
            // Load the default Metal library
            guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
                  let data = try? Data(contentsOf: url) else {
                fatalError("❌ MetaballFilter: Could not load default.metallib. Make sure 'Metaball 2.metal' is added to the target and '-cikernel' flags are set in Build Settings.")
            }
            
            // Initialize the kernel from the Metal function
            return try CIColorKernel(functionName: "thresholdFilter", fromMetalLibraryData: data)
        } catch {
            fatalError("❌ MetaballFilter: Failed to create CIColorKernel: \(error)")
        }
    }()
    
    override var outputImage: CIImage? {
        guard let inputImage = self.inputImage else { return nil }
        
        // 1. Apply Gaussian Blur
        blurFilter.setValue(inputImage, forKey: kCIInputImageKey)
        blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
        
        guard let blurredImage = blurFilter.outputImage else { return nil }
        
        // 2. Apply Threshold Kernel
        // We need to pass the blurred image, the threshold value, the target opacity, and time
        return MetaballFilter.thresholdKernel.apply(
            extent: blurredImage.extent,
            arguments: [blurredImage, Float(threshold), Float(opacity), Float(time)]
        )
    }
}
