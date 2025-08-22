import SpriteKit

final class MainMenuScene: SKScene {
    private let motion: Motion
    private let rainbow = makeRainbowShader(mode: .replace)
    private let holographicNode = SKShapeNode()

    init(size: CGSize, motion: Motion) {
        self.motion = motion
        super.init(size: size)
        scaleMode = .resizeFill
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        
        let rectHeight: CGFloat = 50
        let cornerRadius: CGFloat = 10
        
        let rect = CGRect(x: 0, y: 0, width: size.width, height: rectHeight)
        holographicNode.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        
        holographicNode.position = CGPoint(x: 0, y: 0)
        holographicNode.lineWidth = 0
        holographicNode.fillColor = .white
        holographicNode.fillShader = rainbow
        addChild(holographicNode)
        
        // Initial tuning
        rainbow.set("u_speed", 0.0)
        rainbow.set("u_xfreq", 0.1)
        rainbow.set("u_yfreq", 0.05)
        rainbow.set("u_sat",   1.0)
        rainbow.set("u_val",   1.0)
    }

    override func update(_ t: TimeInterval) {
        // Feed accelerometer (smoothed) to shader
        let ax = Float(motion.accel.dx)
        let ay = Float(motion.accel.dy)
        rainbow.set("u_accel", .init(ax, ay))
    }
}
