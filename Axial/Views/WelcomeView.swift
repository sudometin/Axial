import SwiftUI
import AppKit

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    var body: some View {
        ZStack {
            ScanBackground()

            ScrollView {
                VStack(spacing: 30) {
                    header
                    actions
                    if !model.recents.items.isEmpty { recents }
                    footer
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 40)
                .padding(.vertical, 56)
                .frame(maxWidth: .infinity)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .scrollIndicators(.never)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { appeared = true } }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 104, height: 104)
                .shadow(color: Theme.accent.opacity(0.35), radius: 30)
            Text("Axial")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text("View brain scans and strip patient details from them,\nprivately, on your Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var actions: some View {
        HStack(spacing: 14) {
            ActionCard(
                symbol: "brain.head.profile",
                title: "Open Images",
                subtitle: "NIfTI or a DICOM series folder",
                shortcut: "⌘O"
            ) { model.presentOpenPanel() }

            ActionCard(
                symbol: "checkmark.shield",
                title: "De-identify DICOM",
                subtitle: "Pseudonyms, date shifts, OCR text masking",
                shortcut: "⇧⌘D"
            ) {
                model.selection = .anonymizer
                model.anonymizer.presentAddPanel()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent")
                    .font(.headline)
                Spacer()
                Button("Clear") { withAnimation { model.recents.clear() } }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ForEach(model.recents.items) { item in
                RecentRow(item: item) { model.openRecent(item) }
                if item.id != model.recents.items.last?.id {
                    Divider().padding(.leading, 46)
                }
            }
        }
        .padding(.bottom, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Label("Drop files anywhere. Nothing ever leaves this Mac.", systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("v\(AppInfo.version)")
                Text("·")
                Text("Made by \(AppInfo.author)")
                Text("·")
                Link(destination: AppInfo.profileURL) {
                    Label("github.com/\(AppInfo.githubUser)", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            Text("For research and education. Not a medical device and not for diagnosis.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct RecentRow: View {
    let item: RecentItem
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.isFolder ? "folder.fill" : "doc.fill")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).lineLimit(1)
                    Text((item.path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(item.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct ActionCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    var shortcut: String = ""
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.headline)
                        Spacer()
                        if !shortcut.isEmpty {
                            Text(shortcut)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isHovering ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.07))
            )
            .shadow(color: Theme.accent.opacity(isHovering ? 0.18 : 0), radius: 16)
            .scaleEffect(isHovering ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

/// A quiet animated backdrop: a faint head outline with a slowly sweeping scan line.
struct ScanBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
                let base = min(size.width, size.height) * 0.42

                // Dot grid
                let spacing: CGFloat = 28
                var dots = Path()
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        dots.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                        x += spacing
                    }
                    y += spacing
                }
                context.fill(dots, with: .color(.primary.opacity(0.06)))

                // Concentric head outlines, gently breathing
                for i in 0..<4 {
                    let breathe = 1 + 0.015 * sin(t * 0.8 + Double(i))
                    let w = base * (1.0 - CGFloat(i) * 0.14) * breathe
                    let h = w * 1.2
                    let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
                    context.stroke(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(0.07 - Double(i) * 0.012)), lineWidth: 1.2)
                }

                // Sweeping scan line
                let headHeight = base * 1.2
                let phase = (sin(t * 0.45) + 1) / 2
                let scanY = center.y - headHeight / 2 + headHeight * phase
                let band = CGRect(x: 0, y: scanY - 60, width: size.width, height: 120)
                context.fill(Path(band), with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.06), Theme.accent.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))
                var line = Path()
                line.move(to: CGPoint(x: center.x - base * 0.7, y: scanY))
                line.addLine(to: CGPoint(x: center.x + base * 0.7, y: scanY))
                context.stroke(line, with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.35), Theme.accent.opacity(0)]),
                    startPoint: CGPoint(x: center.x - base * 0.7, y: scanY), endPoint: CGPoint(x: center.x + base * 0.7, y: scanY)),
                    lineWidth: 1)
            }
        }
        .background(
            RadialGradient(colors: [Theme.accent.opacity(0.08), .clear], center: .top, startRadius: 0, endRadius: 700)
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
