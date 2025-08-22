Below is a practical, extensible recipe (with code) for a rainbow gradient shader that animates over x/y, time, and accelerometer, and can be applied to vector paths (incl. SVG via SKShapeNode), SpriteKit nodes, and text. I’ll also call out best‑practices and pitfalls.

Quick reality check on “Metal shader” in SpriteKit:
In SpriteKit you typically write SKShader code (a GLSL‑like fragment shader). SpriteKit compiles it for Metal under the hood and also supports an OpenGL fallback; Apple even recommends making sure it compiles in both renderers. If you truly need to write MSL directly, use SKRenderer to mix SpriteKit with your own Metal pipeline—but for your use case, SKShader is simpler and integrates cleanly with SpriteKit/SwiftUI. 
Apple Developer
+2
Apple Developer
+2

What you can target with one shader

SKSpriteNode → set sprite.shader. 
Apple Developer
+1

SKShapeNode (vector paths, including SVG→CGPath): set shape.fillShader (and/or strokeShader). Use a library like PocketSVG or Macaw to load SVGs as CGPath → SKShapeNode. 
Apple Developer
+1
GitHub
+1

SKLabelNode (text): either wrap the label in an SKEffectNode and set effect.shader, or snapshot the label to a texture and use an SKSpriteNode so you can set sprite.shader directly. (Effect nodes apply a shader to the rendered subtree.) 
Apple Developer

SpriteKit exposes built‑in symbols to your shader: u_time, u_sprite_size, v_tex_coord, u_texture, and, for shapes, path‑related varyings when using stroke/fill shaders. We’ll also add our own uniforms for scroll and accelerometer. 
devstreaming-cdn.apple.com

Best practices (SpriteKit + shaders)

Share shader objects; don’t rebuild per node or per frame. Create one SKShader, attach it to many nodes, and just update its uniform values. Apple’s guidance is to share and initialize at load time. 
devstreaming-cdn.apple.com

Update uniforms, not source. Use SKUniform to pass time scales, scroll, accel, etc. Avoid changing shader.source once compiled. 
Apple Developer

Use built‑ins: u_time (seconds), v_tex_coord (0…1), u_sprite_size (node size). Don’t redeclare built‑ins in your source—SpriteKit injects them. 
devstreaming-cdn.apple.com
Apple Developer

Keep effect nodes scarce. SKEffectNode renders children offscreen; great for applying the shader to text or a group, but it has an extra pass and a few edge‑case bugs (notably bounds issues were reported in iOS 16). Prefer direct node shaders when possible. 
Apple Developer
+1

Watch atlases. If you pack textures into atlases, Xcode may rotate them; use texture coordinates (v_tex_coord) carefully if you see unexpected mapping. Reusing one procedural gradient avoids the issue. 
FreeCodeCamp

SpriteKit + SwiftUI: embed your scene with SpriteView; it renders an SKScene inside SwiftUI. Keep SpriteKit work on the SpriteKit thread (scene callbacks) and SwiftUI state in SwiftUI. 
Apple Developer

Step 1 — Motion input (Core Motion)

Collect accelerometer updates and expose them to the scene for uniforms.

// Motion.swift
import CoreMotion
import Combine

final class Motion: ObservableObject {
    private let mgr = CMMotionManager()
    @Published var accel = CGVector(dx: 0, dy: 0)
    private var lp = CGVector(dx: 0, dy: 0)

    init() {
        guard mgr.isAccelerometerAvailable else { return }
        mgr.accelerometerUpdateInterval = 1.0 / 60.0
        mgr.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            // Low‑pass filter to reduce jitter
            let alpha: CGFloat = 0.12
            let nx = CGFloat(a.x)
            let ny = CGFloat(a.y)
            self.lp.dx = self.lp.dx + alpha * (nx - self.lp.dx)
            self.lp.dy = self.lp.dy + alpha * (ny - self.lp.dy)
            // Scale + clamp to [-1, 1]
            self.accel = CGVector(dx: max(-1, min(1, self.lp.dx)),
                                  dy: max(-1, min(1, self.lp.dy)))
        }
    }
}


Core Motion is the right API for raw accelerometer events (CMMotionManager). You can store it in an ObservableObject and feed SpriteKit via your scene. 
Apple Developer
Create with Swift

Step 2 — SwiftUI container with SpriteView
// ContentView.swift
import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var motion = Motion()

    var scene: GameScene {
        let s = GameScene(size: UIScreen.main.bounds.size, motion: motion)
        s.scaleMode = .resizeFill
        return s
    }

    var body: some View {
        SpriteView(scene: scene,
                   options: [.ignoresSiblingOrder, .shouldCullNonVisibleNodes])
            .ignoresSafeArea()
    }
}


SpriteView is the official SwiftUI host for SpriteKit scenes. 
Apple Developer

Step 3 — The reusable rainbow shader (one source for all nodes)

GLSL fragment (SpriteKit SKShader) – animated rainbow that moves with x/y, time, and accelerometer. It can either replace color or tint the existing texture.

// RainbowShader.swift
import SpriteKit
import simd

enum RainbowMode { case replace, tint }

func makeRainbowShader(mode: RainbowMode = .replace) -> SKShader {
    // One shader for sprites, shapes (fill/stroke), tilemaps, effect nodes, emitters.
    // Uses built-ins: u_time, u_sprite_size, v_tex_coord, SKDefaultShading().
    let src = """
    // HSV -> RGB
    vec3 hsv2rgb(vec3 c){
        vec3 p = abs(fract(c.xxx + vec3(0., 1./3., 2./3.)) * 6. - 3.);
        return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
    }

    void main() {
        // Normalized UVs across the node/effect texture
        vec2 uv = v_tex_coord;

        // Controls supplied from Swift:
        // u_scroll : scroll offset in UV space
        // u_accel  : accelerometer vector (approx -1..1)
        // u_speed  : animation speed (units: cycles/sec)
        // u_xfreq / u_yfreq : spatial frequency along X/Y
        // u_sat / u_val : HSV saturation and value
        // u_mix   : 0=tint base texture, 1=replace (only used when mode==replace in Swift)
        vec2 scroll = u_scroll;
        vec2 accel  = u_accel;

        float t = u_time * u_speed;
        float phase = uv.x * u_xfreq + uv.y * u_yfreq
                      + t
                      + dot(accel, vec2(0.35, 0.25)); // subtle tilt-react

        float hue = fract(phase);
        vec3 rainbow = hsv2rgb(vec3(hue, u_sat, u_val));

        vec4 base = SKDefaultShading(); // sample node’s current look

        #if __RAINBOW_REPLACE__
            gl_FragColor = vec4(rainbow, base.a);
        #else
            // Tint: mix gradient into base color
            float mixAmt = clamp(u_mix, 0.0, 1.0);
            gl_FragColor = mix(base, vec4(rainbow, base.a), mixAmt);
        #endif
    }
    """

    // Pick compile-time path via a tiny preprocessor define:
    let uniforms: [SKUniform] = [
        SKUniform(name: "u_scroll", vectorFloat2: .init(0, 0)),
        SKUniform(name: "u_accel",  vectorFloat2: .init(0, 0)),
        SKUniform(name: "u_speed",  float: 0.25),
        SKUniform(name: "u_xfreq",  float: 1.2),
        SKUniform(name: "u_yfreq",  float: 1.8),
        SKUniform(name: "u_sat",    float: 1.0),
        SKUniform(name: "u_val",    float: 1.0),
        SKUniform(name: "u_mix",    float: 1.0) // used only in tint mode
    ]

    let shader = SKShader(source: src, uniforms: uniforms)
    if mode == .replace {
        shader.source = "#define __RAINBOW_REPLACE__ 1\n" + shader.source
    }
    return shader
}

extension SKShader {
    func set(_ name: String, _ v: vector_float2) {
        if let u = uniforms.first(where: { $0.name == name }) { u.vectorFloat2Value = v }
    }
    func set(_ name: String, _ f: Float) {
        if let u = uniforms.first(where: { $0.name == name }) { u.floatValue = f }
    }
}


Why this works everywhere: we use SpriteKit’s built‑in varyings/uniforms (v_tex_coord, u_time, SKDefaultShading()), so the same code runs on sprites, shape fills/strokes (gradient in vector space), tilemaps, emitters, and effect nodes. Apple documents these built‑ins (including u_time, u_sprite_size, v_tex_coord, SKDefaultShading, and path metrics for shapes). 
devstreaming-cdn.apple.com
Apple Developer

Step 4 — Attach the shader to nodes (sprites, vectors, text)
// GameScene.swift
import SpriteKit

final class GameScene: SKScene {
    private let motion: Motion
    private let rainbow = makeRainbowShader(mode: .replace)

    // Example content
    private let sprite = SKSpriteNode(imageNamed: "photo")
    private let shape  = SKShapeNode(rectOf: CGSize(width: 220, height: 120), cornerRadius: 16)
    private let label  = SKLabelNode(text: "Rainbow")

    // For label, wrap in effect node so the shader runs on the rendered text.
    private let labelEffect = SKEffectNode()

    init(size: CGSize, motion: Motion) {
        self.motion = motion
        super.init(size: size)
        scaleMode = .resizeFill
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = .black

        // Sprite
        sprite.setScale(0.7)
        sprite.position = CGPoint(x: size.width * 0.25, y: size.height * 0.6)
        sprite.shader = rainbow
        addChild(sprite)

        // Vector (shape or SVG path turned into SKShapeNode)
        shape.position = CGPoint(x: size.width * 0.75, y: size.height * 0.6)
        shape.lineWidth = 0
        shape.fillColor = .white
        shape.fillShader = rainbow
        addChild(shape)

        // Text (via effect node)
        label.fontName = "Avenir-Heavy"
        label.fontSize = 64
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center

        labelEffect.shouldEnableEffects = true
        labelEffect.shader = rainbow
        labelEffect.addChild(label)
        labelEffect.position = CGPoint(x: size.width * 0.5, y: size.height * 0.25)
        addChild(labelEffect)

        // Initial tuning
        rainbow.set("u_speed", 0.20)
        rainbow.set("u_xfreq", 1.5)
        rainbow.set("u_yfreq", 1.0)
        rainbow.set("u_sat",   1.0)
        rainbow.set("u_val",   1.0)
    }

    override func update(_ t: TimeInterval) {
        // Scroll the gradient slowly across the whole scene (UV space)
        let s = Float(t * 0.05)
        rainbow.set("u_scroll", .init(s, s))

        // Feed accelerometer (smoothed) to shader
        let ax = Float(motion.accel.dx)
        let ay = Float(motion.accel.dy)
        rainbow.set("u_accel", .init(ax, ay))
    }
}


sprite.shader applies the fragment shader directly to the sprite.

shape.fillShader applies it to a vector fill (handy for SVG → CGPath → SKShapeNode). Use PocketSVG or Macaw to convert SVGs into CGPath you pass to SKShapeNode(path:). 
Apple Developer
GitHub
+1

SKEffectNode.shader lets the shader affect text (or any subtree) since SKLabelNode doesn’t expose a shader property; the effect node renders children to a texture then runs the shader. 
Apple Developer

Adding SVG shapes
// Example: building SKShapeNodes from SVG using PocketSVG
import PocketSVG

func makeShapes(from url: URL) -> [SKShapeNode] {
    let svgPaths = SVGBezierPath.pathsFromSVG(at: url) // PocketSVG API
    return svgPaths.map { p in
        let node = SKShapeNode(path: p.cgPath)
        node.lineWidth = 0
        node.fillColor = .white
        node.fillShader = makeRainbowShader()
        return node
    }
}


PocketSVG provides CGPath for each element in an SVG file; Macaw is another option. Either way, once you have a CGPath, SKShapeNode can render it and your fill/stroke shader does the rest. 
GitHub
+1

Extending the effect later (hooks already included)

Mode toggle (replace vs tint) — already in the shader.

Depth parallax — add u_parallax and include node.zPosition via an attribute (SKAttribute) per node to shift phase. 
Apple Developer

Noise shimmer — add a blue‑noise texture uniform and sample it: texture2D(u_noise, uv*scale + t). 
StudyRaid

Dash/stroke effects for shapes — use strokeShader and path metrics (u_path_length, v_path_distance) to make animated dashes on outlines. 
Apple Developer

Post‑processing across the whole scene — put your world under one SKEffectNode and assign the shader there (mind the performance/edge cases). 
Stack Overflow

Performance & correctness checklist

Create once, reuse: compile one SKShader, attach to many nodes, update uniform values only. 
devstreaming-cdn.apple.com

No per‑frame allocation: keep references to uniforms (shader.uniforms) and change their .floatValue / .vectorFloat2Value. 
Apple Developer

Keep effect nodes minimal: they add an offscreen render; prefer direct node shaders. Some versions had bounds issues; test on your target OS. 
Apple Developer

Use built‑ins: don’t redeclare u_time, u_sprite_size, v_tex_coord. 
Apple Developer

Atlas caution: texture rotation can affect assumptions about v_tex_coord. Procedural effects (no sampling) avoid this. 
FreeCodeCamp