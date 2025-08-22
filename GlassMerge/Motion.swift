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
            let alpha: CGFloat = 0.1
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
