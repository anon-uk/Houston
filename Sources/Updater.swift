// SPDX-License-Identifier: GPL-3.0-or-later
// Houston updater, added 2026-10-09 with AI assistance. See AI_DISCLOSURE.md.
import SwiftUI
import AppKit
import Sparkle

@MainActor final class HoustonUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = HoustonUpdater()
    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []
    @Published var canCheck = false
    @Published var lastCheck: Date?
    var updater: SPUUpdater { controller.updater }
    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        observations = [updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            DispatchQueue.main.async { self?.canCheck = change.newValue ?? false }
        }, updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { guard let self else { return }; self.lastCheck = self.updater.lastUpdateCheckDate }
        }]
        observations += [
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in DispatchQueue.main.async { self?.objectWillChange.send() } },
            updater.observe(\.automaticallyDownloadsUpdates) { [weak self] _, _ in DispatchQueue.main.async { self?.objectWillChange.send() } },
            updater.observe(\.updateCheckInterval) { [weak self] _, _ in DispatchQueue.main.async { self?.objectWillChange.send() } }
        ]
        updater.sendsSystemProfile = false
        controller.startUpdater()
    }
    func check() { controller.checkForUpdates(nil) }
}

struct UpdateSettings: View {
    @ObservedObject private var model = HoustonUpdater.shared
    var body: some View {
        Form {
            Section("Software updates") {
                LabeledContent("Installed version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                Toggle("Automatically check for updates", isOn: Binding(get: {model.updater.automaticallyChecksForUpdates}, set: {model.updater.automaticallyChecksForUpdates = $0}))
                Picker("Check frequency", selection: Binding(get: {model.updater.updateCheckInterval}, set: {model.updater.updateCheckInterval = $0})) { Text("Daily").tag(86400.0); Text("Weekly").tag(604800.0) }
                    .disabled(!model.updater.automaticallyChecksForUpdates)
                Toggle("Automatically download and install updates", isOn: Binding(get: {model.updater.automaticallyDownloadsUpdates}, set: {model.updater.automaticallyDownloadsUpdates = $0})).disabled(!model.updater.automaticallyChecksForUpdates)
                if let date = model.lastCheck { LabeledContent("Last checked") { Text(date, style: .relative) } }
                Button("Check for Updates…") { model.check() }.disabled(!model.canCheck)
                Text("Sparkle verifies signed updates before installation. Updates come from Houston’s public GitHub releases. Only stable releases are offered; monitoring readings and system profiles are not sent.").font(.caption).foregroundStyle(.secondary)
            }

        }.formStyle(.grouped)
    }
}
