// ABOUTME: Preferences window for configuring history limit, polling, and excluded apps.
// ABOUTME: Uses SMAppService for login item management on macOS 13+.

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var preferences: Preferences

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var excludedAppInput = ""

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

                HStack {
                    Text("Polling interval:")
                    TextField("", value: $preferences.pollingInterval, format: .number.precision(.fractionLength(1)))
                        .frame(width: 60)
                    Text("seconds")
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
                HStack {
                    TextField("Bundle ID (e.g., com.example.app)", text: $excludedAppInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard !excludedAppInput.isEmpty else { return }
                        preferences.excludedBundleIDs.insert(excludedAppInput)
                        excludedAppInput = ""
                    }
                }

                if preferences.excludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(preferences.excludedBundleIDs).sorted(), id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.body.monospaced())
                            Spacer()
                            Button("Remove") {
                                preferences.excludedBundleIDs.remove(bundleID)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 350)
        .navigationTitle("Stash Settings")
    }
}
