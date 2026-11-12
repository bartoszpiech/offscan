import Foundation

/// Page rotation in quarter turns **clockwise**.
public enum Rotation: Int, Sendable, Codable, CaseIterable, Hashable {
    case none = 0
    case quarter = 1
    case half = 2
    case threeQuarters = 3

    public func rotatedClockwise() -> Rotation { Rotation(rawValue: (rawValue + 1) % 4)! }
    public func rotatedCounterClockwise() -> Rotation { Rotation(rawValue: (rawValue + 3) % 4)! }
    /// Rotation angle in radians, clockwise positive.
    public var radians: Double { Double(rawValue) * .pi / 2 }
    /// True for 90°/270° — width and height swap.
    public var swapsDimensions: Bool { rawValue % 2 == 1 }
}
