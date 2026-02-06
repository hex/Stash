// ABOUTME: Preferences window for configuring history limit, excluded apps, and about info.
// ABOUTME: Uses SMAppService for login item management and app picker for exclusions.

import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var preferences: Preferences
    var onExcludedAppsChanged: (() -> Void)?

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isPickingApp = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        Form {
            Section("General") {
                HStack {
                    Text("History limit:")
                    TextField("", value: $preferences.historyLimit, format: .number)
                        .frame(width: 80)
                    Text("entries")
                        .foregroundStyle(.secondary)
                }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }

            Section("Excluded Apps") {
                Text("Clipboard content from these apps will be ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if preferences.excludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(preferences.excludedBundleIDs).sorted(), id: \.self) { bundleID in
                        excludedAppRow(bundleID)
                    }
                }

                HStack(spacing: 8) {
                    runningAppsMenu
                    Button("Browse...") { isPickingApp = true }
                }
            }

            Section("About") {
                HStack {
                    Image(systemName: "clipboard")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stash")
                            .font(.headline)
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Clipboard history manager for macOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link("hexul.com", destination: URL(string: "https://hexul.com")!)
                    .font(.caption)

                Text("\u{00A9} hexul")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 440)
        .navigationTitle("Stash Settings")
        .fileImporter(
            isPresented: $isPickingApp,
            allowedContentTypes: [.applicationBundle]
        ) { result in
            if case .success(let url) = result,
               let bundle = Bundle(path: url.path),
               let bundleID = bundle.bundleIdentifier {
                addExcludedApp(bundleID)
            }
        }
    }

    // MARK: - Excluded App Row

    private func excludedAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 10) {
            appIcon(for: bundleID)
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(appName(for: bundleID))
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                removeExcludedApp(bundleID)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Running Apps Menu

    private var runningAppsMenu: some View {
        Menu("Add Running App...") {
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
                .filter { !preferences.excludedBundleIDs.contains($0.bundleIdentifier!) }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

            if apps.isEmpty {
                Text("All running apps are excluded")
            } else {
                ForEach(apps, id: \.bundleIdentifier) { app in
                    Button {
                        if let id = app.bundleIdentifier {
                            addExcludedApp(id)
                        }
                    } label: {
                        if let icon = app.icon {
                            Label {
                                Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                            } icon: {
                                Image(nsImage: icon)
                            }
                        } else {
                            Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                        }
                    }
                }
            }
        }
    }

    // MARK: - App Resolution

    private func appIcon(for bundleID: String) -> Image {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: "questionmark.app")
    }

    private func appName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    // MARK: - Actions

    private func addExcludedApp(_ bundleID: String) {
        preferences.excludedBundleIDs.insert(bundleID)
        onExcludedAppsChanged?()
    }

    private func removeExcludedApp(_ bundleID: String) {
        preferences.excludedBundleIDs.remove(bundleID)
        onExcludedAppsChanged?()
    }
}
