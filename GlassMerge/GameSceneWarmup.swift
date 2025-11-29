import SpriteKit

extension GameScene {
    // Warm up the render pipeline for the Metaball effect
    func warmUpMetaballEffect() {
        // Create a small off-screen effect node
        let effectNode = SKEffectNode()
        effectNode.shouldEnableEffects = true
        
        // Use the Metaball filter
        let filter = MetaballFilter()
        filter.blurRadius = 10.0
        filter.threshold = 0.5
        filter.opacity = 0.8
        effectNode.filter = filter
        
        // Add a dummy child to render
        let dummyNode = SKSpriteNode(color: .white, size: CGSize(width: 10, height: 10))
        effectNode.addChild(dummyNode)
        
        // Position off-screen
        effectNode.position = CGPoint(x: -1000, y: -1000)
        
        // Add to scene to trigger pipeline preparation
        addChild(effectNode)
        
        // Remove after a short delay (allowing one frame to render)
        let removeAction = SKAction.sequence([
            SKAction.wait(forDuration: 0.1),
            SKAction.removeFromParent()
        ])
        effectNode.run(removeAction)
    }
}
