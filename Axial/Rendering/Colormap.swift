import Foundation

enum Colormap: String, CaseIterable, Identifiable {
    case gray = "Gray"
    case bone = "Bone"
    case hot = "Hot"
    case viridis = "Viridis"

    var id: String { rawValue }

    /// Evenly spaced RGB control points (0–255).
    var stops: [(Double, Double, Double)] {
        switch self {
        case .gray: [(0, 0, 0), (255, 255, 255)]
        case .bone: [(0, 0, 0), (84, 84, 116), (167, 199, 199), (255, 255, 255)]
        case .hot: [(0, 0, 0), (230, 0, 0), (255, 210, 0), (255, 255, 255)]
        case .viridis: [
            (68, 1, 84), (72, 40, 120), (62, 73, 137), (49, 104, 142), (38, 130, 142),
            (31, 158, 137), (53, 183, 121), (109, 205, 89), (180, 222, 44), (253, 231, 37),
        ]
        }
    }

    func rgb(at t: Double) -> (Double, Double, Double) {
        let s = stops
        let x = min(max(t, 0), 1) * Double(s.count - 1)
        let i = min(Int(x), s.count - 2)
        let f = x - Double(i)
        let a = s[i], b = s[i + 1]
        return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
    }

    /// 256 entries packed as RGBX bytes in memory order (little-endian UInt32).
    var lut: [UInt32] { Colormap.tables[self]! }

    private static let tables: [Colormap: [UInt32]] = {
        var tables: [Colormap: [UInt32]] = [:]
        for map in Colormap.allCases {
            var table = [UInt32](repeating: 0, count: 256)
            for i in 0..<256 {
                let (r, g, b) = map.rgb(at: Double(i) / 255)
                let red = UInt32(r.rounded())
                let green = UInt32(g.rounded()) << 8
                let blue = UInt32(b.rounded()) << 16
                table[i] = red | green | blue | 0xFF00_0000
            }
            tables[map] = table
        }
        return tables
    }()
}
