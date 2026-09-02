import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var hotKeyManager: HotKeyManager
    @ObservedObject var store: ClipboardStore
    let pasteManager: PasteManager

    @State private var accessibilityGranted = false
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Picker("Global Shortcut", selection: $settings.shortcutID) {
                    ForEach(ShortcutChoice.choices) { choice in
                        Text(choice.title).tag(choice.id)
                    }
                }

                if let error = hotKeyManager.registrationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Stepper("History Limit: \(settings.historyLimit)", value: $settings.historyLimit, in: 10...1_000, step: 10)

                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))

                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                Toggle("Automatically paste selected item", isOn: $settings.automaticallyPaste)
            }

            Section("Accessibility") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(accessibilityGranted ? "Permission granted" : "Permission needed for automatic paste")
                            .fontWeight(.medium)
                        Text("ClipBoard uses Accessibility only to send Command-V after restoring the app you were using.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Refresh") { refreshAccessibility() }
                    Spacer()
                    Button("Open System Settings…") {
                        pasteManager.requestAccessibilityPermission()
                        pasteManager.openAccessibilitySettings()
                    }
                }
            }

            Section {
                Button("Clear Clipboard History", role: .destructive) { confirmClear = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 470, height: 430)
        .onAppear(perform: refreshAccessibility)
        .alert("Clear all clipboard history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Everything", role: .destructive) { store.clear(preservingPinned: false) }
        } message: {
            Text("This also removes pinned items and cannot be undone.")
        }
    }

    private func refreshAccessibility() {
        accessibilityGranted = pasteManager.hasAccessibilityPermission
    }
}
