import Foundation

/// One step of a breathing pattern.
enum Step {
    case inhale(Double)
    case holdFull(Double)
    case exhale(Double)
    case holdEmpty(Double)

    var seconds: Double {
        switch self {
        case .inhale(let s), .holdFull(let s), .exhale(let s), .holdEmpty(let s): return s
        }
    }
}

/// A named breathing rhythm shown in the menu.
struct Pace {
    let id: String
    let name: String
    let detail: String
    let steps: [Step]

    var cycle: Double { steps.reduce(0) { $0 + $1.seconds } }

    static let all: [Pace] = [
        Pace(id: "slow", name: "Slow", detail: "5.5 in · 5.5 out", steps: [.inhale(5.5), .exhale(5.5)]),
        Pace(id: "calm", name: "Long out", detail: "4 in · 6 out", steps: [.inhale(4), .exhale(6)]),
        Pace(id: "gentle", name: "Gentle", detail: "4 in · 4 out", steps: [.inhale(4), .exhale(4)]),
        Pace(id: "box", name: "Box", detail: "4 in, hold, out, hold", steps: [.inhale(4), .holdFull(4), .exhale(4), .holdEmpty(4)]),
    ]

    static func named(_ id: String) -> Pace { all.first { $0.id == id } ?? all[0] }

    /// How full the lungs are at time `t`: 0 is empty, 1 is full.
    func level(at t: Double) -> Double {
        var x = t.truncatingRemainder(dividingBy: cycle)
        if x < 0 { x += cycle }
        for step in steps {
            if x < step.seconds {
                let p = x / step.seconds
                switch step {
                case .inhale: return ease(p)
                case .holdFull: return 1
                case .exhale: return 1 - ease(p)
                case .holdEmpty: return 0
                }
            }
            x -= step.seconds
        }
        return 0
    }

    private func ease(_ p: Double) -> Double { (1 - cos(Double.pi * p)) / 2 }
}
