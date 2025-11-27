import SpriteKit

extension GameScene {
    func runMetaballMerge(nodeA: SKSpriteNode, nodeB: SKSpriteNode, nextTier: Int, completion: (() -> Void)? = nil) {
        let middlePoint = CGPoint(x: (nodeA.position.x + nodeB.position.x) / 2,
                                  y: (nodeA.position.y + nodeB.position.y) / 2)
        
        // 1. Create the new sphere immediately (for physics) but hide it
        // This ensures other balls react to the new presence, though we'll scale it up
        guard let newSphere = createAndPlaceSphere(at: middlePoint, tier: nextTier) else { return }
        
        // Make merged spheres immediately "live" for the danger zone
        newSphere.userData?["creationTime"] = Date.distantPast.timeIntervalSinceReferenceDate
        
        // Start invisible and small
        newSphere.alpha = 0.0
        let targetScale: CGFloat = 1.0
        let startScale: CGFloat = 0.7
        newSphere.setScale(startScale)
        
        // 2. Create Effect Node for the Metaball visuals
        let effectNode = SKEffectNode()
        effectNode.shouldEnableEffects = true
        
        // Configure the Metaball Filter
        let filter = MetaballFilter()
        filter.blurRadius = 10.0
        filter.threshold = 0.5
        effectNode.filter = filter
        
        effectNode.position = middlePoint
        effectNode.zPosition = 100
        addChild(effectNode)
        
        // 3. Create Visual Clones of the merging balls
        func createClone(from original: SKSpriteNode) -> SKSpriteNode {
            let clone = SKSpriteNode(texture: original.texture)
            clone.size = original.size
            clone.color = original.color
            clone.colorBlendFactor = original.colorBlendFactor
            
            // Calculate relative position: original world pos - middle point
            let relativeX = original.position.x - middlePoint.x
            let relativeY = original.position.y - middlePoint.y
            clone.position = CGPoint(x: relativeX, y: relativeY)
            
            return clone
        }
        
        // Capture properties before nodes might be removed/modified
        let cloneA = createClone(from: nodeA)
        let cloneB = createClone(from: nodeB)
        
        effectNode.addChild(cloneA)
        effectNode.addChild(cloneB)
        
        // 4. Animate Clones Merging
        // Make the merge much faster (snappier)
        let moveDuration: TimeInterval = 0.1 // Reduced from 0.2
        let moveAction = SKAction.move(to: .zero, duration: moveDuration)
        moveAction.timingMode = .easeIn
        
        // Run animation on clones
        cloneA.run(moveAction)
        cloneB.run(moveAction)
        
        // 5. Finalize Transition
        // IMPORTANT: Run this action on the SCENE to ensure it runs even if newSphere physics state changes
        // Using a safer approach to ensure effectNode is removed.
        
        let waitAction = SKAction.wait(forDuration: moveDuration)
        let finishAction = SKAction.run { [weak self, weak newSphere, weak effectNode] in
            // Always remove the effect node
            effectNode?.removeFromParent()
            
            guard let newSphere = newSphere else { return }
            
            // Reveal the new sphere
            newSphere.alpha = 1.0
            
            // "Grow" / Pop effect to final size
            // Also make the grow snappier
            let growAction = SKAction.scale(to: targetScale, duration: 0.1) // Reduced from 0.15
            growAction.timingMode = .easeOut
            
            newSphere.run(growAction) {
                completion?()
            }
        }
        
        // Run the sequence on the scene to guarantee cleanup.
        self.run(SKAction.sequence([waitAction, finishAction]))
    }
}
