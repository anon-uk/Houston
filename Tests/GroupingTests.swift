// SPDX-License-Identifier: GPL-3.0-or-later
// Portable: Foundation only, runs on macOS and Linux.
import Foundation
@main struct GroupingTests {
    static func p(_ id: Int32, parent: Int32 = 1, uid: UInt32 = 501, _ name: String, _ path: String, app: Bool = false, responsible: Int32 = 0) -> ProcessIdentity {
        ProcessIdentity(id: id, parent: parent, uid: uid, name: name, path: path, app: app, responsible: responsible)
    }
    static func main() {
        precondition(appBundlePrefix("/Applications/Xcode.app/Contents/MacOS/Xcode") == "/Applications/Xcode.app/")
        precondition(appBundlePrefix("/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator") == "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/")
        precondition(appBundlePrefix("/usr/bin/zsh") == nil)
        let procs = [
            p(10, "Google Chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", app: true),
            p(11, parent: 10, "Google Chrome Helper", "/Applications/Google Chrome.app/Contents/Frameworks/G.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"),
            p(12, parent: 11, "Google Chrome Helper (Renderer)", "/Applications/Google Chrome.app/Contents/Frameworks/G.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/x"),
            p(20, "Mail", "/System/Applications/Mail.app/Contents/MacOS/Mail", app: true),
            // launchd-reparented WebKit process attributed by responsibility.
            p(21, "com.apple.WebKit.WebContent", "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent", responsible: 20),
            p(30, "Xcode", "/Applications/Xcode.app/Contents/MacOS/Xcode", app: true),
            p(31, "Simulator", "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator", app: true),
            p(32, "SimulatorHelper", "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/XPCServices/H.xpc/Contents/MacOS/H"),
            p(33, "SourceKitService", "/Applications/Xcode.app/Contents/SharedFrameworks/S.framework/XPCServices/SourceKitService.xpc/Contents/MacOS/SourceKitService"),
            // Two instances of one app: bundle helpers are ambiguous.
            p(40, "Editor", "/Applications/Editor.app/Contents/MacOS/Editor", app: true),
            p(41, "Editor", "/Applications/Editor.app/Contents/MacOS/Editor", app: true),
            p(42, "EditorAgent", "/Applications/Editor.app/Contents/XPCServices/A.xpc/Contents/MacOS/A"),
            p(50, "Safari", "/Applications/Safari.app/Contents/MacOS/Safari", app: true),
            p(51, "Blocker", "/Applications/Blocker.app/Contents/PlugIns/Blocker Extension.appex/Contents/MacOS/Blocker Extension"),
            p(52, "Safari Networking", "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/com.apple.WebKit.Networking"),
            // Unrelated daemons: self-responsible, other user, no app bundle.
            p(60, uid: 0, "mds", "/System/Library/Frameworks/CoreServices.framework/mds", responsible: 60),
            p(61, uid: 0, "someroot", "/Applications/Google Chrome.app/Contents/Library/root-helper"),
            // Parent cycle must terminate.
            p(70, parent: 71, "a", "/tmp/a"), p(71, parent: 70, "b", "/tmp/b"),
        ]
        let owners = groupOwners(procs, isSafariApp: { $0 == 50 }, isSafariExtension: { $0.contains(".appex/") })
        let expected: [Int32: Int32?] = [10: 10, 11: 10, 12: 10, 20: 20, 21: 20, 30: 30, 31: 31, 32: 31, 33: 30, 40: 40, 41: 41, 42: nil, 50: 50, 51: 50, 52: 50, 60: nil, 61: nil, 70: nil, 71: nil]
        for (id, owner) in expected { precondition(owners[id] == owner, "pid \(id): expected \(String(describing: owner)), got \(String(describing: owners[id]))") }
        print("PASS: ancestry, responsible process, nested bundles, Safari extensions, WebKit names, ambiguity, cycles")
    }
}
