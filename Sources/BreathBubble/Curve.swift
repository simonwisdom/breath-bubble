import Foundation

/// A timing curve written the way CSS writes one, cubic-bezier(x1, y1, x2, y2): time in, amount out, both 0...1.
struct Curve {
    let x1: Double, y1: Double, x2: Double, y2: Double

    /// Going into focus: the dark starts the moment you double-click, then settles slowly.
    static let arrive = Curve(x1: 0.2, y1: 0.45, x2: 0.45, y2: 1)
    /// Coming out of focus: starts gently, then clears away.
    static let leave = Curve(x1: 0.5, y1: 0, x2: 0.7, y2: 0.7)

    func callAsFunction(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        // Find the curve parameter s whose x is t (x rises with s), then return its y.
        var lo = 0.0, hi = 1.0, s = t
        for _ in 0..<24 {
            let x = bezier(s, x1, x2)
            if abs(x - t) < 1e-6 { break }
            if x < t { lo = s } else { hi = s }
            s = (lo + hi) / 2
        }
        return bezier(s, y1, y2)
    }

    private func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
    }
}
