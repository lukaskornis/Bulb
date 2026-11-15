import CoreGraphics

/// Moves all screens together: by equal steps, or keeping the brightness ratios last set screen by screen.
final class ScreenGroup {
    var screens: [Screen] = [] {
        didSet { captureRatios() }
    }
    var keepsRatios = false {
        didSet { captureRatios() }
    }
    private var ratios: [CGDirectDisplayID: Float] = [:]

    var controllable: [Screen] { screens.filter(\.isControllable) }

    /// With ratios kept, the brightest screen is the level and the others follow it.
    var level: Float {
        let values = controllable.map(\.brightness)
        guard !values.isEmpty else { return 1 }
        return keepsRatios ? values.max() ?? 1 : values.reduce(0, +) / Float(values.count)
    }

    /// Call after a single screen was changed on its own, so its new look becomes the reference.
    func captureRatios() {
        let values = controllable.map { ($0.id, $0.brightness) }
        let top = values.map(\.1).max() ?? 0
        ratios = Dictionary(uniqueKeysWithValues: values.map { ($0.0, top > 0 ? $0.1 / top : 1) })
    }

    func setLevel(_ level: Float) {
        let clamped = min(max(level, 0), 1)
        for screen in controllable {
            screen.set(keepsRatios ? (ratios[screen.id] ?? 1) * clamped : clamped)
        }
    }

    /// Moves every other screen after one that changed: by the same amount, or keeping ratios.
    func follow(_ leader: Screen, delta: Float) {
        let others = controllable.filter { $0 !== leader }
        guard keepsRatios, let leaderRatio = ratios[leader.id], leaderRatio > 0 else {
            others.forEach { $0.set($0.brightness + delta) }
            return
        }
        let level = leader.brightness / leaderRatio
        others.forEach { $0.set((ratios[$0.id] ?? 1) * level) }
    }
}
