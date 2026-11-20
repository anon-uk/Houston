// SPDX-License-Identifier: GPL-3.0-or-later
// Houston process grouping, 2026-11-20, with AI assistance. See AI_DISCLOSURE.md.
import Foundation

struct ProcessIdentity: Equatable {
    var id: Int32; var parent: Int32; var uid: UInt32; var name: String; var path: String; var app: Bool
    // The process macOS holds responsible (TCC, energy); 0 when unknown.
    var responsible: Int32 = 0
}

// The enclosing bundle of an app's executable, e.g. "/Applications/X.app/".
// Searching backwards picks the innermost bundle, so an app nested inside
// another app's bundle (Simulator inside Xcode) owns its own helpers.
func appBundlePrefix(_ path: String) -> String? {
    guard let range = path.range(of: ".app/Contents/", options: .backwards) else { return nil }
    return String(path[..<path.index(range.lowerBound, offsetBy: 5)])
}

// Maps each process to the regular app it belongs to; apps map to themselves.
// Unattributable processes are absent rather than guessed. In order:
// 1. Parent ancestry. 2. The macOS responsible process and its ancestry
// (WebKit, XPC services and launchd-reparented helpers). 3. Safari extensions.
// 4. The innermost app bundle containing the executable. 5. WebKit/XPC names.
func groupOwners(_ procs: [ProcessIdentity], isSafariApp: (Int32) -> Bool, isSafariExtension: (String) -> Bool) -> [Int32: Int32] {
    let byID = Dictionary(procs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let roots = procs.filter(\.app)
    let rootPrefixes = roots.compactMap { root in appBundlePrefix(root.path).map { (root, $0) } }
    func appAncestor(_ start: Int32) -> Int32? {
        var cursor = start, seen: Set<Int32> = []
        while cursor > 1, seen.insert(cursor).inserted, let p = byID[cursor] {
            if p.app { return p.id }
            cursor = p.parent
        }
        return nil
    }
    var result: [Int32: Int32] = [:]
    for p in procs {
        if p.app { result[p.id] = p.id; continue }
        if let owner = appAncestor(p.parent) { result[p.id] = owner; continue }
        if p.responsible > 1, p.responsible != p.id, let owner = appAncestor(p.responsible) { result[p.id] = owner; continue }
        if isSafariExtension(p.path) {
            let safari = roots.filter { $0.uid == p.uid && isSafariApp($0.id) }
            if safari.count == 1 { result[p.id] = safari[0].id; continue }
        }
        let containing = rootPrefixes.filter { $0.0.uid == p.uid && p.path.hasPrefix($0.1) }
        if let longest = containing.map({ $0.1.count }).max() {
            let best = containing.filter { $0.1.count == longest }
            if best.count == 1 { result[p.id] = best[0].0.id; continue }
            // Several instances of the same app: ambiguous, leave ungrouped.
            continue
        }
        if p.path.contains("/XPCServices/") {
            let named = roots.filter { root in
                root.uid == p.uid && root.path.contains(".app/") &&
                (p.name.hasSuffix(" (" + root.name + ")") || (p.path.contains("com.apple.WebKit") && p.name.hasPrefix(root.name + " ")))
            }
            if named.count == 1 { result[p.id] = named[0].id }
        }
    }
    return result
}
