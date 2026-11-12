#if DEBUG
import Foundation

/// Deterministic pseudo-random numbers (SplitMix64), so demo artwork looks the same on every run.
struct DemoRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `range`.
    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        let unit = CGFloat(next() >> 11) / CGFloat(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    /// Uniform in `range`.
    mutating func next(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }
}
#endif
