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
                      + dot(accel, vec2(0.925, 0.625)); // Balanced tilt-react

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
        shader.source = "#define __RAINBOW_REPLACE__ 1\n" + (shader.source ?? "")
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
