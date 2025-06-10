# SpriteKit Physics and Game Area Reference

## Layout Constants
```swift
struct Layout {
    static let containerMargin: CGFloat = 20.0
    static let gridSpacing: CGFloat = 40.0
    static let gridDotSize: CGFloat = 2.0
    static let topBarHeight: CGFloat = 40.0
    static let bottomBarHeight: CGFloat = 100.0
    static let cornerRadius: CGFloat = 20.0
    static let boundaryLineWidth: CGFloat = 2.0
    static let spawnHeight: CGFloat = 60.0
    static let dangerLineWidth: CGFloat = 2.0
}
```

## Physics Categories
```swift
struct PhysicsCategory {
    static let none: UInt32 = 0
    static let all: UInt32 = UInt32.max
    static let material: UInt32 = 0x1
    static let boundary: UInt32 = 0x1 << 1
    static let dangerZone: UInt32 = 0x1 << 2
}
```

## Physics Constants
```swift
struct PhysicsConstants {
    static let maxVelocity: CGFloat = 1000.0
    static let maxAngularVelocity: CGFloat = 20.0
    static let velocityDampingThreshold: CGFloat = 800.0  // When to start extra damping
    static let extraDampingFactor: CGFloat = 0.8  // How much to dampen high velocities
}
```

## Game Area Setup
```swift
private func setupGameArea() {
    let gameArea = SKNode()
    
    // Calculate dimensions
    let gameWidth = size.width - (Layout.containerMargin * 2)
    let gameHeight = size.height - Layout.topBarHeight - Layout.bottomBarHeight - Layout.containerMargin - Layout.topBarPadding - Layout.topBarGameAreaSpacing - Layout.safeAreaTopPadding
    
    // Position below top bar
    gameArea.position = CGPoint(x: Layout.containerMargin, 
                              y: Layout.bottomBarHeight + Layout.containerMargin)
    
    // Create visible boundary with rounded corners
    let boundaryRect = CGRect(x: 0, y: 0, width: gameWidth, height: gameHeight)
    let boundaryPath = CGPath(roundedRect: boundaryRect,
                            cornerWidth: Layout.cornerRadius,
                            cornerHeight: Layout.cornerRadius,
                            transform: nil)
    
    let boundaryNode = SKShapeNode(path: boundaryPath)
    boundaryNode.strokeColor = .gray.withAlphaComponent(0.5)
    boundaryNode.lineWidth = Layout.boundaryLineWidth
    gameArea.addChild(boundaryNode)
    
    // Create physics boundaries
    let boundaryLayers = createBoundaryLayers(width: gameWidth, height: gameHeight)
    boundaryLayers.forEach { gameArea.addChild($0) }
    
    addChild(gameArea)
    self.gameArea = gameArea
}
```

## Boundary Physics Setup
```swift
private func createBoundaryLayers(width: CGFloat, height: CGFloat) -> [SKNode] {
    var boundaryNodes: [SKNode] = []
    
    // Main rounded boundary
    let mainBoundary = SKNode()
    let mainPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                        cornerWidth: Layout.cornerRadius,
                        cornerHeight: Layout.cornerRadius,
                        transform: nil)
    let mainPhysics = SKPhysicsBody(edgeLoopFrom: mainPath)
    configureBoundaryPhysics(mainPhysics)
    mainBoundary.physicsBody = mainPhysics
    boundaryNodes.append(mainBoundary)
    
    // Multiple bottom boundaries for better collision
    let bottomOffsets: [CGFloat] = [-1.0, -2.0, -3.0]
    let extraWidth: CGFloat = 4.0
    
    for offset in bottomOffsets {
        let bottomBoundary = SKNode()
        let bottomPath = CGMutablePath()
        bottomPath.move(to: CGPoint(x: -extraWidth, y: offset))
        bottomPath.addLine(to: CGPoint(x: width + extraWidth, y: offset))
        
        let bottomPhysics = SKPhysicsBody(edgeChainFrom: bottomPath)
        configureBoundaryPhysics(bottomPhysics)
        bottomPhysics.mass *= 2.0
        bottomPhysics.restitution = 0.4
        
        bottomBoundary.physicsBody = bottomPhysics
        boundaryNodes.append(bottomBoundary)
    }
    
    // Side boundaries with overlap
    let sideOffsets: [CGFloat] = [-2.0, 2.0]
    for offset in sideOffsets {
        let sideBoundary = SKNode()
        let sidePath = CGMutablePath()
        let x = offset < 0 ? -2.0 : width + 2.0
        sidePath.move(to: CGPoint(x: x, y: -5.0))
        sidePath.addLine(to: CGPoint(x: x, y: height))
        
        let sidePhysics = SKPhysicsBody(edgeChainFrom: sidePath)
        configureBoundaryPhysics(sidePhysics)
        sideBoundary.physicsBody = sidePhysics
        boundaryNodes.append(sideBoundary)
    }
    
    return boundaryNodes
}

private func configureBoundaryPhysics(_ physics: SKPhysicsBody) {
    physics.categoryBitMask = PhysicsCategory.boundary
    physics.collisionBitMask = PhysicsCategory.material
    physics.friction = 0.05
    physics.restitution = 0.3
    physics.isDynamic = false
    physics.usesPreciseCollisionDetection = true
    physics.mass = 1000000
    physics.linearDamping = 0.0
    physics.angularDamping = 0.0
}
```

## Danger Zone Setup
```swift
private func setupDangerZone() {
    guard let gameArea = gameArea else { return }
    
    // Calculate dimensions
    let gameWidth = size.width - (Layout.containerMargin * 2)
    let gameHeight = size.height - Layout.topBarHeight - Layout.bottomBarHeight - Layout.containerMargin - Layout.topBarPadding
    
    let spawnY = gameHeight - Layout.spawnHeight
    let dangerZoneHeight = gameHeight - spawnY
    
    // Create sensor node
    let sensor = SKNode()
    sensor.position = CGPoint(x: 0, y: spawnY)
    sensor.name = "dangerZone"
    
    // Setup collision detection
    let sensorBody = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: 0, width: gameWidth, height: dangerZoneHeight))
    sensorBody.isDynamic = false
    sensorBody.affectedByGravity = false
    sensorBody.allowsRotation = false
    sensorBody.mass = 0
    sensorBody.friction = 0
    sensorBody.restitution = 0
    sensorBody.linearDamping = 0
    sensorBody.angularDamping = 0
    sensorBody.categoryBitMask = PhysicsCategory.dangerZone
    sensorBody.contactTestBitMask = PhysicsCategory.material
    sensorBody.collisionBitMask = 0  // No physical collision
    sensorBody.usesPreciseCollisionDetection = true
    sensor.physicsBody = sensorBody
    
    // Visual elements
    let zoneArea = SKShapeNode(rect: CGRect(x: 0, y: spawnY, width: gameWidth, height: dangerZoneHeight))
    zoneArea.fillColor = .clear
    zoneArea.strokeColor = .clear
    zoneArea.name = "dangerZoneArea"
    zoneArea.zPosition = 1
    
    let bottomLine = SKShapeNode()
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: spawnY))
    path.addLine(to: CGPoint(x: gameWidth, y: spawnY))
    bottomLine.path = path
    bottomLine.strokeColor = .gray.withAlphaComponent(0.5)
    bottomLine.lineWidth = Layout.dangerLineWidth
    bottomLine.name = "dangerLine"
    bottomLine.zPosition = 2
    
    gameArea.addChild(sensor)
    gameArea.addChild(zoneArea)
    gameArea.addChild(bottomLine)
}
```

## Physics World Setup
```swift
private func setupPhysics() {
    physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
    physicsWorld.speed = 1.0
    physicsWorld.contactDelegate = self
}
```

## Velocity Management
```swift
private func capVelocity(for body: SKPhysicsBody) {
    // Cap linear velocity
    let currentVelocity = body.velocity
    let speed = sqrt(currentVelocity.dx * currentVelocity.dx + currentVelocity.dy * currentVelocity.dy)
    
    if speed > PhysicsConstants.maxVelocity {
        let scale = PhysicsConstants.maxVelocity / speed
        body.velocity = CGVector(dx: currentVelocity.dx * scale, dy: currentVelocity.dy * scale)
    } else if speed > PhysicsConstants.velocityDampingThreshold {
        let dampingScale = PhysicsConstants.extraDampingFactor
        body.velocity = CGVector(dx: currentVelocity.dx * dampingScale, dy: currentVelocity.dy * dampingScale)
    }
    
    // Cap angular velocity
    if abs(body.angularVelocity) > PhysicsConstants.maxAngularVelocity {
        body.angularVelocity = PhysicsConstants.maxAngularVelocity * (body.angularVelocity < 0 ? -1 : 1)
    }
}
``` 