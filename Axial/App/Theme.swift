import SwiftUI
import AppKit

/// Project links and version, shown in About, Help and the welcome screen.
enum AppInfo {
    /// ← Change this to your GitHub username.
    static let githubUser = "maasker"
    static let author = "Matin Hassanloo"

    static var repositoryURL: URL { URL(string: "https://github.com/\(githubUser)/Axial")! }
    static var profileURL: URL { URL(string: "https://github.com/\(githubUser)")! }
    static var issuesURL: URL { URL(string: "https://github.com/\(githubUser)/Axial/issues")! }

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Shared colours. Each anatomical plane has its own colour, used for its label and
/// for the crosshair line that marks it in the other two views.
enum Theme {
    static let accent = Color(red: 0.25, green: 0.84, blue: 0.84)
    static let canvas = Color(red: 0.035, green: 0.04, blue: 0.05)

    static func color(_ plane: Plane) -> Color { Color(nsColor(plane)) }

    static func nsColor(_ plane: Plane) -> NSColor {
        switch plane {
        case .axial: NSColor(red: 0.25, green: 0.84, blue: 0.84, alpha: 1)   // teal
        case .coronal: NSColor(red: 0.69, green: 0.52, blue: 1.0, alpha: 1) // violet
        case .sagittal: NSColor(red: 1.0, green: 0.66, blue: 0.30, alpha: 1) // amber
        }
    }
}

/// A small rounded "pill" used for overlay labels on images.
struct HUDPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
            .environment(\.colorScheme, .dark)
    }
}

/// Selectable capsule button used for presets.
struct ChipButton: View {
    let title: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isSelected ? Theme.accent.opacity(0.22) : Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Theme.accent.opacity(0.7) : Color.primary.opacity(0.08))
                )
                .foregroundStyle(isSelected ? Theme.accent : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
