import SwiftUI
import AppKit

@main
struct AxialApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 660)
                .tint(Theme.accent)
        }
        .windowToolbarStyle(.unified)
        .commands { AxialCommands(model: model) }

        Window("About Axial", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
    }
}

struct AxialCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Axial") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open…") { model.presentOpenPanel() }
                .keyboardShortcut("o")
            Button("De-identify DICOM…") {
                model.selection = .anonymizer
                model.anonymizer.presentAddPanel()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Link("Axial on GitHub", destination: AppInfo.repositoryURL)
            Link("Report an Issue…", destination: AppInfo.issuesURL)
            Divider()
            Link("\(AppInfo.author) on GitHub", destination: AppInfo.profileURL)
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: Theme.accent.opacity(0.35), radius: 24)
            VStack(spacing: 4) {
                Text("Axial")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Version \(AppInfo.version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("A native MRI viewer and DICOM de-identifier.\nEverything runs on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Link(destination: AppInfo.repositoryURL) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.borderedProminent)
                Link(destination: AppInfo.issuesURL) {
                    Label("Report Issue", systemImage: "ladybug")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            Divider().padding(.vertical, 4)

            VStack(spacing: 3) {
                Text("Made by \(AppInfo.author)")
                    .font(.callout.weight(.medium))
                Link("github.com/\(AppInfo.githubUser)", destination: AppInfo.profileURL)
                    .font(.callout)
                Text("MIT License · For research and education, not for diagnosis.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(width: 400)
        .tint(Theme.accent)
    }
}
