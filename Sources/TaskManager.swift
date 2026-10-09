// SPDX-License-Identifier: GPL-3.0-or-later
// Native adaptations modified for Houston, 2026-10-09. See THIRD-PARTY-NOTICES.md and AI_DISCLOSURE.md.
import SwiftUI
import AppKit
import Charts
import IOKit
import Darwin
import Combine

func bytes(_ value: Double) -> String { value < 1 ? "0 KB" : ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .memory) }
func pct(_ value: Double) -> String { String(format: "%.1f%%", value) }
func cString<T>(_ value: T) -> String { var v = value; return withUnsafePointer(to: &v) { $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) } } }
func run(_ path: String, _ args: [String]) -> (Int32, String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
    do { try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "") }
    catch { return (-1, error.localizedDescription) }
}
// IOKit property names and GPU sampling approach adapted from exelban/Stats (MIT).
func registry(_ service: String) -> [(UInt64, [String: Any])] {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(service), &iterator) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }; var result: [(UInt64, [String: Any])] = []
    var entry = IOIteratorNext(iterator)
    while entry != 0 {
        var properties: Unmanaged<CFMutableDictionary>?
        var id: UInt64 = 0; IORegistryEntryGetRegistryEntryID(entry, &id)
        if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS, let properties { result.append((id, properties.takeRetainedValue() as NSDictionary as? [String: Any] ?? [:])) }
        IOObjectRelease(entry); entry = IOIteratorNext(iterator)
    }; return result
}
func ioProperties(_ entry:io_registry_entry_t) -> [String:Any] {
    var value:Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry,&value,kCFAllocatorDefault,0)==KERN_SUCCESS,let value else { return [:] }
    return value.takeRetainedValue() as NSDictionary as? [String:Any] ?? [:]
}
struct GPUReading: Identifiable { var id: UInt64; var name: String; var usage: Double; var render: Double?; var tiler: Double? }
struct DiskCounter: Identifiable { var id: UInt64; var name: String; var read: Double; var write: Double; var bsd: String = ""; var capacity: Double = 0 }
struct DiskRate { var read: Double = 0; var write: Double = 0 }
struct HardwareReading { var gpus: [GPUReading] = []; var disks: [DiskCounter] = [] }
func readHardware() -> HardwareReading {
    var out = HardwareReading()
    for (id, props) in registry("IOAccelerator") {
        guard let stats = props["PerformanceStatistics"] as? [String: Any], let usage = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber else { continue }
        out.gpus.append(GPUReading(id: id, name: props["model"] as? String ?? props["IOClass"] as? String ?? "GPU", usage: min(100, max(0, usage.doubleValue)), render: (stats["Renderer Utilization %"] as? NSNumber)?.doubleValue, tiler: (stats["Tiler Utilization %"] as? NSNumber)?.doubleValue))
    }
    var iterator:io_iterator_t=0
    if IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOBlockStorageDriver"),&iterator)==KERN_SUCCESS {
        var entry=IOIteratorNext(iterator)
        while entry != 0 {
            let props=ioProperties(entry)
            if let stats=props["Statistics"] as? [String:Any],let read=stats["Bytes (Read)"] as? NSNumber,let write=stats["Bytes (Write)"] as? NSNumber {
                var id:UInt64=0;IORegistryEntryGetRegistryEntryID(entry,&id)
                var name="Physical disk",bsd="";var capacity:Double=0
                var parent:io_registry_entry_t=0
                if IORegistryEntryGetParentEntry(entry,kIOServicePlane,&parent)==KERN_SUCCESS {
                    let device=ioProperties(parent)
                    if let characteristics=device["Device Characteristics"] as? [String:Any] { name=characteristics["Product Name"] as? String ?? name }
                    IOObjectRelease(parent)
                }
                var descendants:io_iterator_t=0
                if IORegistryEntryCreateIterator(entry,kIOServicePlane,IOOptionBits(kIORegistryIterateRecursively),&descendants)==KERN_SUCCESS {
                    var media=IOIteratorNext(descendants)
                    while media != 0 {
                        let properties=ioProperties(media)
                        if IOObjectConformsTo(media,"IOMedia") != 0,properties["Whole"] as? Bool == true, ((properties["Size"] as? NSNumber)?.doubleValue ?? 0) > capacity {
                            bsd=properties["BSD Name"] as? String ?? "";capacity=(properties["Size"] as? NSNumber)?.doubleValue ?? 0
                            if name == "Physical disk",let mediaName=properties["IOName"] as? String { name=mediaName }
                        }
                        IOObjectRelease(media);media=IOIteratorNext(descendants)
                    };IOObjectRelease(descendants)
                }
                out.disks.append(DiskCounter(id:id,name:name,read:read.doubleValue,write:write.doubleValue,bsd:bsd,capacity:capacity))
            }
            IOObjectRelease(entry);entry=IOIteratorNext(iterator)
        };IOObjectRelease(iterator)
    }
    out.disks.sort { $0.bsd == $1.bsd ? $0.id<$1.id : $0.bsd<$1.bsd }

    return out
}
@MainActor final class IconCache {
    static let shared = IconCache()
    var icons: [String: NSImage] = [:]
    var safariExtensionPaths:[String:Bool]=[:]
    func isSafariExtension(_ path:String) -> Bool {
        if let cached=safariExtensionPaths[path] {return cached}
        var result=false
        if let range=path.range(of:".appex/") {
            let bundlePath=String(path[..<range.upperBound].dropLast())
            if let extensionInfo=Bundle(path:bundlePath)?.infoDictionary?["NSExtension"] as? [String:Any],let point=extensionInfo["NSExtensionPointIdentifier"] as? String {
                result=point == "com.apple.Safari.web-extension" || point == "com.apple.Safari.extension"
            }
        }
        safariExtensionPaths[path]=result;return result
    }
    func icon(_ path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let parts = path.components(separatedBy: ".app/")
        let target = parts.count > 1 ? parts[0] + ".app" : path
        let image: NSImage
        if target == Bundle.main.bundlePath,let url=Bundle.main.url(forResource:"TaskManager",withExtension:"icns"),let bundled=NSImage(contentsOf:url) {image=bundled} else {image=NSWorkspace.shared.icon(forFile:target.isEmpty ? "/usr/bin" : target)}
        icons[path] = image; return image
    }
}
struct SidebarGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular, in: Rectangle()) }
        else { content.background(.ultraThinMaterial) }
    }
}
struct Proc: Identifiable {
    var id: Int32; var parent: Int32; var uid: UInt32; var name: String; var path: String; var cpu: Double; var memory: Double; var threads: Int; var cpuTime: Double; var diskRead: Double?; var diskWrite: Double?; var start: UInt64; var app: Bool = false; var state: String = "Running"; var userName: String = ""
    var user: String {userName.isEmpty ? String(uid) : userName}
    var kind: String { app ? "App" : (uid == 0 ? "System process" : "Background process") }
    var disk: Double { (diskRead ?? 0) + (diskWrite ?? 0) }
}
struct ProcessIdentity:Equatable {
    var id:Int32;var parent:Int32;var uid:UInt32;var name:String;var path:String;var app:Bool
    init(_ p:Proc) {id=p.id;parent=p.parent;uid=p.uid;name=p.name;path=p.path;app=p.app}
}
@MainActor final class OwnershipCache {
    static let shared=OwnershipCache()
    var identities:[ProcessIdentity]=[]
    var owners:[Int32:Int32]=[:]
}
struct HistoryRow: Identifiable, Codable { var id: String; var name: String; var cpu: Double = 0; var read: Double = 0; var write: Double = 0; var lastSeen: Date = Date() }
struct ServiceRow: Identifiable { var id: String; var pid: String; var exit: String; var scope: String; var path: String = ""; var status: String { pid == "-" ? "Stopped" : "Running" } }
struct StartupRow: Identifiable { var id: String; var name: String; var path: String; var scope: String; var trigger: String }
struct UserRow: Identifiable { var id: UInt32; var name: String; var cpu: Double; var memory: Double; var count: Int }
struct Sample: Identifiable { var id = UUID(); var date: Date; var cpu: Double; var memory: Double; var network: Double; var disk: Double; var gpu: Double; var kernel: Double; var coreUsage: [Double]; var coreKernel: [Double]; var receive: Double; var send: Double; var read: Double; var write: Double; var disks:[UInt64:DiskRate] }
enum Page: String, CaseIterable, Identifiable {
    case processes = "Processes", performance = "Performance", history = "App history", startup = "Startup apps", users = "Users", details = "Details", services = "Services", settings = "Settings"
    var id: String { rawValue }
    var icon: String { switch self { case .processes: return "square.stack.3d.up"; case .performance: return "waveform.path.ecg"; case .history: return "clock.arrow.circlepath"; case .startup: return "speedometer"; case .users: return "person.2"; case .details: return "list.bullet.rectangle"; case .services: return "gearshape.2"; case .settings: return "gearshape" } }
}

@MainActor final class Monitor: ObservableObject {
    @Published var processes: [Proc] = []
    @Published var system = TMSystem()
    @Published var hardware = HardwareReading()
    @Published var samples: [Sample] = []
    @Published var history: [HistoryRow] = []
    @Published var services: [ServiceRow] = []
    @Published var startup: [StartupRow] = []
    @Published var paused = false
    @Published var interval: Double = UserDefaults.standard.double(forKey: "interval") == 0 ? 2 : UserDefaults.standard.double(forKey: "interval")
    @Published var error: String? = nil
    @Published var netIn: Double = 0
    @Published var netOut: Double = 0
    @Published var diskRead: Double = 0
    @Published var diskWrite: Double = 0
    @Published var diskRates:[UInt64:DiskRate] = [:]
    @Published var page: Page = .processes
    @Published var query = ""
    @Published var selected: Int32?
    @Published var inspector: Proc?
    @Published var group = true
    @Published var alwaysOnTop = false { didSet { applyWindowLevel() } }
    @Published var compact = false
    var previous: [Int32: TMProcess] = [:]; var previousSystem: TMSystem?; var previousHardware = HardwareReading(); var lastTime: Date?; var timer: Timer?; var busy = false; var ticks = 0
    var userNames:[UInt32:String]=[:]
    var statusGadgets: StatusGadgets?
    var openMainWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?
    var historySince = UserDefaults.standard.object(forKey: "historySince") as? Date ?? Date()
    let historyURL: URL
    init() {
        historyURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeTaskManager/history.json")
        if let data = try? Data(contentsOf: historyURL), let rows = try? JSONDecoder().decode([HistoryRow].self, from: data) { history = rows; if UserDefaults.standard.integer(forKey:"historyVersion") < 2 { var tb=mach_timebase_info_data_t();mach_timebase_info(&tb);for i in history.indices { history[i].cpu *= Double(tb.numer)/Double(tb.denom) };UserDefaults.standard.set(2,forKey:"historyVersion") } }
        UserDefaults.standard.set(historySince, forKey: "historySince")
        page = Page(rawValue:UserDefaults.standard.string(forKey:"defaultPage") ?? "Processes") ?? .processes
        if page == .settings {page = .processes}
        statusGadgets = StatusGadgets(monitor:self)
        restartTimer(); refresh(); refreshServices()
    }
    func restartTimer() {
        timer?.invalidate(); UserDefaults.standard.set(interval, forKey: "interval")
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in Task { @MainActor in guard let self, !self.paused else { return }; self.refresh() } }
        timer?.tolerance = min(0.1, interval * 0.1)
    }
    func refresh() {
        guard !busy else { return }; busy = true
        Task.detached(priority: .utility) {
            let capacity = max(4096, Int(proc_listallpids(nil,0)) + 1024)
            var raw = [TMProcess](repeating: TMProcess(), count: capacity)
            let count = tm_processes(&raw, Int32(raw.count)); let procs = Array(raw.prefix(Int(count))); let system = tm_system(); let hardware = readHardware()
            await self.consume(procs, system, hardware)
        }
    }
    func consume(_ raw: [TMProcess], _ stats: TMSystem, _ hw: HardwareReading) {
        let now = Date(); let elapsed = max(0.05, now.timeIntervalSince(lastTime ?? now)); let apps = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a,_ in a })
        var histories = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { a,_ in a })
        let cpuDivisor = Double(UserDefaults.standard.object(forKey:"normalizeCPU") as? Bool == false ? 1 : max(1,stats.cores))
        for uid in Set(raw.map {UInt32($0.uid)}) where userNames[uid] == nil {userNames[uid] = getpwuid(uid).map {String(cString:$0.pointee.pw_name)} ?? String(uid)}
        processes = raw.map { r in
            let old = previous[r.pid]; let valid = old?.started == r.started
            let cpu = valid && r.cpu_ns >= old!.cpu_ns ? Double(r.cpu_ns - old!.cpu_ns) / 1e9 / elapsed : 0
            let rd = valid && r.io_valid != 0 && old!.io_valid != 0 && r.read_bytes >= old!.read_bytes ? Double(r.read_bytes - old!.read_bytes) / elapsed : nil
            let wr = valid && r.io_valid != 0 && old!.io_valid != 0 && r.write_bytes >= old!.write_bytes ? Double(r.write_bytes - old!.write_bytes) / elapsed : nil
            let app = apps[r.pid]; let name = app?.localizedName ?? cString(r.name); let path = cString(r.path)
            if valid && r.uid == getuid() {
                let key = path.isEmpty ? name : path; var h = histories[key] ?? HistoryRow(id: key, name: name)
                h.cpu += cpu * elapsed; h.read += (rd ?? 0) * elapsed; h.write += (wr ?? 0) * elapsed; h.lastSeen = now; histories[key] = h
            }
            return Proc(id: r.pid, parent: r.ppid, uid: UInt32(r.uid), name: name, path: path, cpu: cpu * 100 / cpuDivisor, memory: Double(r.resident), threads: Int(r.threads), cpuTime: Double(r.cpu_ns)/1e9, diskRead: rd, diskWrite: wr, start: r.started, app: app?.activationPolicy == .regular, state: app?.isTerminated == true ? "Exited" : "Running", userName:userNames[UInt32(r.uid)] ?? String(r.uid))
        }
        if let old = previousSystem, lastTime != nil { netIn = Double(stats.net_in >= old.net_in ? stats.net_in-old.net_in : 0)/elapsed; netOut = Double(stats.net_out >= old.net_out ? stats.net_out-old.net_out : 0)/elapsed }
        diskRead = 0; diskWrite = 0;diskRates = [:]
        for d in hw.disks { if let old = previousHardware.disks.first(where: { $0.id == d.id }) { let rd=max(0,d.read-old.read)/elapsed, wr=max(0,d.write-old.write)/elapsed;diskRates[d.id]=DiskRate(read:rd,write:wr);diskRead += rd;diskWrite += wr } }
        system = stats; hardware = hw; previousHardware = hw; previousSystem = stats; previous = Dictionary(raw.map { ($0.pid, $0) }, uniquingKeysWith: { a,_ in a }); lastTime = now
        history = Array(histories.values).sorted { $0.cpu > $1.cpu }; ticks += 1
        if ticks % 15 == 0 { saveHistory() }
        if previous.count > 0 && ticks > 1 { samples.append(Sample(date: now, cpu: stats.cpu, memory: Double(stats.memory_used)/Double(max(1, stats.memory_total))*100, network: netIn+netOut, disk: diskRead+diskWrite, gpu: hw.gpus.first?.usage ?? 0, kernel:stats.kernel,coreUsage:doubleArray(stats.core_usage,count:min(128,Int(stats.cores))),coreKernel:doubleArray(stats.core_kernel,count:min(128,Int(stats.cores))),receive:netIn,send:netOut,read:diskRead,write:diskWrite,disks:diskRates)) }
        samples.removeAll { now.timeIntervalSince($0.date) > 320 }; busy = false
    }
    func saveHistory() { do { try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(history).write(to: historyURL, options: .atomic) } catch { self.error = "Unable to save usage history: \(error.localizedDescription)" } }
    func clearHistory() {
        let alert=NSAlert();alert.messageText="Delete recorded usage history?";alert.informativeText="This permanently removes the resource usage recorded by Houston. New history will start recording immediately. This cannot be undone.";alert.alertStyle = .warning;alert.addButton(withTitle:"Delete History");alert.addButton(withTitle:"Cancel");guard alert.runModal() == .alertFirstButtonReturn else {return}
        history = []; historySince = Date(); UserDefaults.standard.set(historySince, forKey: "historySince"); saveHistory() }
    func applyWindowLevel() { NSApp.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.level = alwaysOnTop ? .floating : .normal } }
    var chosen: Proc? { processes.first { $0.id == selected } }
    var users: [UserRow] { Dictionary(grouping: processes, by: \.uid).map { uid, rows in UserRow(id: uid, name: rows[0].user, cpu: rows.reduce(0){$0+$1.cpu}, memory: rows.reduce(0){$0+$1.memory}, count: rows.count) }.sorted { $0.cpu > $1.cpu } }
    func canControl(_ proc:Proc?) -> Bool { guard let proc else {return false};return proc.id > 1 && proc.id != getpid() && proc.uid == getuid() }
    func processAction(_ action: String, proc: Proc) {
        guard proc.id > 1, proc.id != getpid(), proc.uid == getuid() else { error = "This process is protected or owned by another user."; return }
        guard let current = processes.first(where: { $0.id == proc.id && $0.start == proc.start }) else { error = "The process has exited."; return }
        var raw = proc_bsdinfo(); let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(current.id, PROC_PIDTBSDINFO, 0, &raw, size) == size, raw.pbi_start_tvsec == current.start else { error = "The selected process has exited or changed."; return }
        let alert = NSAlert(); alert.messageText = "\(action) \(current.name)?"; alert.informativeText = action == "End task" || action == "Force quit" ? "Unsaved work in this process may be lost." : "This changes the scheduling of the selected process."; alert.addButton(withTitle: action); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let result: Int32
        switch action { case "End task": result = kill(current.id, SIGTERM); case "Force quit": result = kill(current.id, SIGKILL); case "Suspend": result = kill(current.id, SIGSTOP); case "Resume": result = kill(current.id, SIGCONT); default: result = setpriority(PRIO_PROCESS, UInt32(current.id), 10) }
        if result != 0 { error = String(cString: strerror(errno)) }; refresh()
    }
    func runTask() { let panel = NSOpenPanel(); panel.title = "Run new task"; panel.message = "Choose an application, executable, or document to open."; panel.canChooseDirectories = false; if panel.runModal() == .OK, let url = panel.url { NSWorkspace.shared.open(url) } }
    func openLoginItems() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!) }
    func refreshServices() {
        Task.detached(priority: .utility) {
            let result = run("/bin/launchctl", ["list"]); var rows: [ServiceRow] = []
            if result.0 == 0 { for line in result.1.split(separator: "\n").dropFirst() { let parts = line.split(whereSeparator: \.isWhitespace); if parts.count >= 3 { rows.append(ServiceRow(id: String(parts[2]), pid: String(parts[0]), exit: String(parts[1]), scope: "Current user")) } } }
            var startups: [StartupRow] = []
            let folders = [(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path, "Current user"), ("/Library/LaunchAgents", "All users"), ("/Library/LaunchDaemons", "System")]
            for (folder, scope) in folders {
                for url in (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "plist" {
                    guard let data = try? Data(contentsOf: url), let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                    let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                    let trigger = dict["RunAtLoad"] as? Bool == true ? "At login / load" : (dict["KeepAlive"] != nil ? "Keep alive" : "On demand / schedule")
                    startups.append(StartupRow(id: url.path, name: label, path: url.path, scope: scope, trigger: trigger))
                    if let i = rows.firstIndex(where: { $0.id == label }) { rows[i].path = url.path }
                }
            }
            await self.setServices(rows, startups, result.0 == 0 ? nil : result.1)
        }
    }
    func setServices(_ rows: [ServiceRow], _ items: [StartupRow], _ err: String?) { services = rows.sorted { $0.id < $1.id }; startup = items.sorted { $0.name < $1.name }; if let err { error = err } }
    func serviceAction(_ action: String, _ row: ServiceRow) {
        let alert = NSAlert(); alert.messageText = "\(action) \(row.id)?"; alert.informativeText = "This affects the selected launchd job in your current login session. Keep-alive jobs may restart automatically."; alert.addButton(withTitle: action); alert.addButton(withTitle: "Cancel"); guard alert.runModal() == .alertFirstButtonReturn else { return }
        let target = "gui/\(getuid())/\(row.id)"; let args = action == "Stop" ? ["kill", "SIGTERM", target] : ["kickstart", "-k", target]
        Task.detached { let result = run("/bin/launchctl", args); await self.serviceResult(result) }
    }
    func serviceResult(_ result: (Int32, String)) { if result.0 != 0 { error = result.1.isEmpty ? "launchd denied the operation." : result.1 }; refreshServices() }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "processes.csv"; if panel.runModal() != .OK { return }; guard let url = panel.url else { return }
        func csv(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let content = "Name,PID,User,CPU percent of total machine,Resident bytes,Threads,Read bytes per second,Write bytes per second,Path\n" + processes.map { "\(csv($0.name)),\($0.id),\(csv($0.user)),\($0.cpu),\($0.memory),\($0.threads),\($0.diskRead.map { String($0) } ?? ""),\($0.diskWrite.map { String($0) } ?? ""),\(csv($0.path))" }.joined(separator: "\n")
        do { try content.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
    }
}

struct GlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10)) }
        else { content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
    }
}
struct ResourceCell: View {
    var value: String; var intensity: Double; var color: Color = .accentColor
    @AppStorage("grayZeroes") var grayZeroes = true
    var body: some View { Text(value).foregroundStyle(grayZeroes && (value == "0.0%" || value == "0 KB/s") ? Color.secondary : Color.primary).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing).padding(.vertical, 4).padding(.horizontal, 2) }
}
struct MiniGraph: View {
    var samples: [Sample]; var key: KeyPath<Sample, Double>; var color: Color
    var body: some View { Chart(samples) { s in AreaMark(x: .value("Time", s.date), y: .value("Value", s[keyPath: key])).foregroundStyle(color.opacity(0.12)); LineMark(x: .value("Time", s.date), y: .value("Value", s[keyPath: key])).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1)) }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: 0...max(100, samples.map { $0[keyPath:key] }.max() ?? 100)).frame(width: 74, height: 42).border(color.opacity(0.7)) }
}
func doubleArray<T>(_ value: T, count: Int) -> [Double] { var v=value; return withUnsafePointer(to:&v) { $0.withMemoryRebound(to:Double.self,capacity:count) { Array(UnsafeBufferPointer(start:$0,count:count)) } } }
struct LivePlot: View {
    var points: [PlotPoint]; var secondary: [PlotPoint] = []; var end: Date; var seconds: Double; var maximum: Double; var color: Color; var filled: Bool; var mini = false
    @AppStorage("smoothGraphs") var smooth = false
    @AppStorage("slidingGraphs") var sliding = true
    @AppStorage("animations") var animations = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var animate = true
    var valueLabel: (Double) -> String = {pct($0)}
    var secondaryLabel = "Kernel"
    var accessibilityName = "Utilization"
    @State private var hover: CGPoint?
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:mini || !(sliding && animations && !reduceMotion && animate))) { frame in
            let drawingEnd = !mini && sliding && animations && !reduceMotion && animate ? end.addingTimeInterval(min(4,max(0,frame.date.timeIntervalSince(end)))) : end
            canvas(drawingEnd)
        }
    }
    func canvas(_ drawingEnd:Date) -> some View {
        Canvas { context, size in
            let width=size.width, height=size.height
            var grid=Path()
            // Mission Center graph-widget grid: approximately 60x50 points.
            let columns=max(1,Int((width/60).rounded())+1),rows=max(1,Int((height/50).rounded())+1)
            let columnWidth=width/Double(columns)
            let phase = sliding && animate && !mini ? (-drawingEnd.timeIntervalSinceReferenceDate*width/seconds).truncatingRemainder(dividingBy:columnWidth) : 0
            for i in 0...columns+1 { let x=width*Double(i)/Double(columns)+phase;grid.move(to:CGPoint(x:x,y:0));grid.addLine(to:CGPoint(x:x,y:height)) }
            for i in 1..<rows { let y=height*Double(i)/Double(rows);grid.move(to:CGPoint(x:0,y:y));grid.addLine(to:CGPoint(x:width,y:y)) }
            if !mini { context.stroke(grid,with:.color(color.opacity(0.20)),lineWidth:0.5) }
            func draw(_ values:[PlotPoint], dashed:Bool) {
                let visible=boundedPlot(values,end:drawingEnd,seconds:seconds)
                guard !visible.isEmpty else { return }
                var path=Path(); var first:CGPoint?; var last:CGPoint?
                for value in visible {
                    let x=width*(1+value.date.timeIntervalSince(drawingEnd)/seconds)
                    let y=height*(1-min(1,max(0,value.value/max(1,maximum))))
                    let point=CGPoint(x:x,y:y)
                    if first == nil { path.move(to:point);first=point }
                    else if smooth,let previous=last { let dx=(point.x-previous.x)/2;path.addCurve(to:point,control1:CGPoint(x:previous.x+dx,y:previous.y),control2:CGPoint(x:point.x-dx,y:point.y)) }
                    else { path.addLine(to:point) };last=point
                }
                if filled && !dashed, let first,let last { var area=path;area.addLine(to:CGPoint(x:last.x,y:height));area.addLine(to:CGPoint(x:first.x,y:height));area.closeSubpath();context.fill(area,with:.color(color.opacity(0.26))) }
                context.stroke(path,with:.color(dashed ? color.opacity(0.72) : color),style:StrokeStyle(lineWidth:1,dash:dashed ? [5,5] : []))
            }
            draw(points,dashed:false);draw(secondary,dashed:true)
            if let hover,!mini { var line=Path();line.move(to:CGPoint(x:hover.x,y:0));line.addLine(to:CGPoint(x:hover.x,y:height));context.stroke(line,with:.color(color.opacity(0.6)),style:StrokeStyle(lineWidth:0.7,dash:[2,3])) }
        }
        .clipShape(RoundedRectangle(cornerRadius:7))
        .overlay { RoundedRectangle(cornerRadius:7).stroke(color.opacity(0.9),lineWidth:0.7).allowsHitTesting(false) }
        .overlay(alignment:.topLeading) {
            GeometryReader { geometry in
                let target=drawingEnd.addingTimeInterval(-seconds*(1-(hover?.x ?? 0)/max(1,geometry.size.width)))
                if let hover,!mini,let sample=points.min(by:{abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))}) {
                    VStack(alignment:.leading,spacing:4) {
                        Text(sample.date,style:.time).foregroundStyle(.secondary)
                        Text(valueLabel(sample.value)).monospacedDigit()
                        if let second=secondary.min(by:{abs($0.date.timeIntervalSince(sample.date)) < abs($1.date.timeIntervalSince(sample.date))}) {Text(secondaryLabel+": "+valueLabel(second.value)).monospacedDigit()}
                    }.font(.caption).padding(9).frame(width:min(180,max(1,geometry.size.width-8)),alignment:.leading).background(.regularMaterial,in:RoundedRectangle(cornerRadius:7)).offset(x:graphTooltipX(pointer:hover.x,width:geometry.size.width,tooltipWidth:min(180,max(1,geometry.size.width-8))),y:min(max(8,hover.y-65),max(8,geometry.size.height-90)))
                }
            }.allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in switch phase { case .active(let p):hover=p;case .ended:hover=nil } }
        .accessibilityLabel(accessibilityName + " graph, last \(Int(seconds)) seconds")
        .accessibilityValue(points.last.map { valueLabel($0.value) } ?? "No samples yet")
    }
}
struct NativeWindowSetup:NSViewRepresentable {
    final class WindowView:NSView {
        override func viewDidMoveToWindow() {super.viewDidMoveToWindow();window?.isMovableByWindowBackground=true;window?.titlebarAppearsTransparent=true}
        override var mouseDownCanMoveWindow:Bool {true}
    }
    func makeNSView(context:Context) -> NSView {WindowView()}
    func updateNSView(_ view:NSView,context:Context) {view.window?.isMovableByWindowBackground=true}
}
struct MainView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettings
    @EnvironmentObject var m: Monitor
    @AppStorage("appearance") var appearance = "System"
    @State var sortOrder = [KeyPathComparator(\Proc.cpu, order: .reverse)]
    @State var metric = "CPU"
    @State var serviceSelection: String?
    @State var startupSelection: String?
    @State var userSelection: UInt32?
    @State var historySelection: String?
    @State var userFilter: UInt32?
    @State var collapsed = false
    @State var columnVisibility:NavigationSplitViewVisibility = .all
    @State var collapsedGroups: Set<String> = []
    @State private var searchPresented = false
    @State var expandedApps: Set<Int32> = []
    @State var serviceFilter="All"
    @AppStorage("detailsPosition") var detailsPosition="Right"
    @AppStorage("graphDuration") var graphDuration = 60.0
    @AppStorage("smoothGraphs") var smoothGraphs = false
    @AppStorage("slidingGraphs") var slidingGraphs = true
    @AppStorage("graphFill") var graphFill = true
    @AppStorage("showMiniGraphs") var showMiniGraphs = true
    @AppStorage("cpuGraphMode") var cpuGraphMode = "Overall utilization"
    @AppStorage("showKernelTimes") var showKernelTimes = false
    @AppStorage("networkBits") var networkBits = true
    @AppStorage("animations") var animations = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var searchPrompt:String { switch m.page {case .history:return "Search recorded processes";case .services:return "Search services";case .startup:return "Search startup items";case .performance:return "Search performance metrics";case .settings:return "Search settings";default:return "Search name, PID, or user"} }
    var motion:Animation? {animations && !reduceMotion ? .smooth(duration:0.22) : nil}
    var filtered: [Proc] { m.processes.filter { (m.query.isEmpty || "\($0.name) \($0.id) \($0.user) \($0.path)".localizedCaseInsensitiveContains(m.query)) && (userFilter == nil || $0.uid == userFilter) }.sorted(using: sortOrder) }
    var body: some View { AnyView(mainContent) }
    @ViewBuilder var rootLayout:some View {
        if m.compact {detailContent} else {
            NavigationSplitView(columnVisibility:$columnVisibility) {
                sidebar.navigationSplitViewColumnWidth(min:220,ideal:240,max:300)
            } detail: {detailContent}
            .navigationSplitViewStyle(.balanced)
        }
    }
    var detailContent:some View {
        VStack(spacing:0) {
            content.frame(maxWidth:.infinity,maxHeight:.infinity).id(m.page).transition(.opacity.combined(with:.offset(y:reduceMotion ? 0 : 4)))

        }.background(Color(nsColor:.windowBackgroundColor))
        .navigationTitle(m.page.rawValue)
    }
    var mainContent: some View {
        rootLayout.background(NativeWindowSetup().allowsHitTesting(false)).frame(minWidth:m.compact ? 560 : 780,minHeight:m.compact ? 360 : 560)
        
        .animation(animations && !reduceMotion ? .smooth(duration:0.24) : nil,value:collapsed)
        .animation(animations && !reduceMotion ? .smooth(duration:0.24) : nil,value:m.compact)
        .animation(animations && !reduceMotion ? .smooth(duration:0.22) : nil,value:cpuGraphMode)
        .animation(motion,value:metric)
        .animation(motion,value:showMiniGraphs)
        .animation(motion,value:detailsPosition)
        .toolbar {
            ToolbarItemGroup(placement:.automatic) {pageActions}
            if m.page != .settings { ToolbarItemGroup(placement: .primaryAction) {
                Button { m.runTask() } label: { Label("Run new task", systemImage: "plus.square") }.help("Run new task")
                Button { m.paused.toggle() } label: { Label(m.paused ? "Resume" : "Pause", systemImage: m.paused ? "play.fill" : "pause.fill") }
            }
        } }
        .searchable(text:$m.query,isPresented:$searchPresented,placement:m.compact ? .toolbar : .sidebar,prompt:Text("Search"))
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("TaskManagerFind"))) { _ in if m.page == .settings || m.page == .performance {m.page = .processes};searchPresented=true }
        .toolbarBackgroundVisibility(.hidden, for:.windowToolbar)
        .onAppear {m.openMainWindow = {openWindow(id:"main");NSApp.activate(ignoringOtherApps:true)};m.openSettingsWindow = {openSettings();NSApp.activate(ignoringOtherApps:true)}}
        .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
        .alert("Unable to complete action", isPresented: Binding(get: {m.error != nil}, set: { if !$0 { m.error = nil } })) { Button("OK") { m.error = nil } } message: { Text(m.error ?? "") }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.willTerminateNotification)) { _ in m.saveHistory() }
        .sheet(item: $m.inspector) { proc in Inspector(proc: proc).environmentObject(m) }
        .onChange(of: m.page) { _, _ in m.query = ""; userFilter = nil; if m.page == .services || m.page == .startup { m.refreshServices() } }
    }
    var sidebar: some View {
        List(selection:Binding<Page?>(get:{m.page},set:{if let page=$0 {m.page=page}})) {
            Section("Monitor") {
                ForEach(Page.allCases.filter {$0 != .settings}) { page in
                    HStack(alignment:.center,spacing:10) {
                        Image(systemName:page.icon).font(.system(size:16,weight:.regular)).frame(width:22,height:22).accessibilityHidden(true)
                        Text(page.rawValue).font(.body).lineLimit(1)
                        Spacer(minLength:0)
                    }.frame(height:26).tag(page)
                    .listRowInsets(EdgeInsets(top:5,leading:10,bottom:5,trailing:10))
                }
            }
        }.listStyle(.sidebar).environment(\.defaultMinListRowHeight,36)
        .transaction {$0.animation=nil}
        .safeAreaInset(edge:.bottom) {
            Text(ProcessInfo.processInfo.hostName).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(16)
        }
    }
    var nativeSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search name, PID, or user", text: $m.query).textFieldStyle(.plain)
            if !m.query.isEmpty { Button { m.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
        }.padding(.horizontal, 13).padding(.vertical, 8).frame(width: 320).modifier(GlassSurface())
    }
    var topbar: some View {
        HStack { Text("Houston").font(.system(size: 13, weight: .semibold)); Spacer(); HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search name, PID, or user", text: $m.query).textFieldStyle(.plain); if !m.query.isEmpty { Button { m.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) } }.padding(9).frame(width: 310).modifier(GlassSurface()); Spacer(); Button { m.paused.toggle() } label: { Image(systemName: m.paused ? "play.fill" : "pause.fill") }.buttonStyle(.borderless).help(m.paused ? "Resume updates" : "Pause updates") }.padding(.horizontal, 20).padding(.vertical, 13)
    }
    @ViewBuilder var pageActions:some View {
        if m.page == .processes || m.page == .details {
            Button {if let p=m.chosen {m.processAction("End task",proc:p)}} label: {Label("End Task",systemImage:"xmark.octagon")}.disabled(!m.canControl(m.chosen)).help("End the selected process")
            Menu {
                if m.page == .processes {Button(collapsedGroups.count == 3 ? "Expand All Groups" : "Collapse All Groups") {collapsedGroups=collapsedGroups.count == 3 ? [] : Set(["App","Background process","System process"])}}
                Toggle("Group by Type",isOn:$m.group)
                Button("Export Process List…") {m.export()}
                Button("Refresh Now") {m.refresh()}
                if let p=m.chosen {Divider();processMenu(p)}
            } label: {Label("Process Options",systemImage:"ellipsis.circle")}.help("Process options")
        } else if m.page == .history {
            Button {m.clearHistory()} label: {Label("Delete Usage History",systemImage:"trash")}
        } else if m.page == .startup {
            Button("Manage Login Items…") {m.openLoginItems()}
        } else if m.page == .services {
            Button {m.refreshServices()} label: {Label("Refresh",systemImage:"arrow.clockwise")}
            if let row=m.services.first(where:{$0.id == serviceSelection}) {Button("Start") {m.serviceAction("Start",row)};Button("Stop") {m.serviceAction("Stop",row)}.disabled(row.pid == "-")}
        }
    }
    @ViewBuilder var content: some View {
        switch m.page {
        case .processes: processTable
        case .details: detailsTable
        case .performance: performance
        case .history: historyTable
        case .startup: startupTable
        case .users: usersTable
        case .services: servicesTable
        case .settings: SettingsContent().environmentObject(m)
        }
    }
    @ViewBuilder func processMenu(_ p: Proc) -> some View {
        Button("Inspect process") { m.inspector = p }
        Button("Open file location") { if !p.path.isEmpty { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.path)]) } }.disabled(p.path.isEmpty)
        Button("Copy PID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(p.id), forType: .string) }
        Divider()
        ForEach(["End task", "Force quit", "Suspend", "Resume", "Efficiency mode"], id: \.self) { action in Button(action) { m.processAction(action, proc: p) }.disabled(!m.canControl(p)) }
    }
    // Parent ancestry is authoritative; bundle paths also retain launchd-reparented helpers.
    var appOwners: [Int32:Int32] {
        let identities=m.processes.map {ProcessIdentity($0)}
        let cache=OwnershipCache.shared
        if cache.identities == identities {return cache.owners}
        let byID=Dictionary(uniqueKeysWithValues:m.processes.map {($0.id,$0)})
        let roots=m.processes.filter { $0.app }
        var result:[Int32:Int32]=[:]
        for p in m.processes {
            if p.app { result[p.id]=p.id;continue }
            var cursor=p.parent;var seen:Set<Int32>=[]
            while cursor>1,seen.insert(cursor).inserted,let ancestor=byID[cursor] {
                if ancestor.app {result[p.id]=ancestor.id;break};cursor=ancestor.parent
            }
            if result[p.id] == nil,IconCache.shared.isSafariExtension(p.path) {
                let safari=roots.filter {$0.uid == p.uid && NSRunningApplication(processIdentifier:$0.id)?.bundleIdentifier == "com.apple.Safari"}
                if safari.count == 1 {result[p.id]=safari[0].id}
            }
            if result[p.id] == nil {
                let matches=roots.filter { root in
                    guard root.uid == p.uid,let range=root.path.range(of: ".app/") else {return false}
                    return p.path.hasPrefix(String(root.path[..<range.upperBound])) || (p.path.contains("/XPCServices/") && (p.name.hasSuffix(" ("+root.name+")") || (p.path.contains("com.apple.WebKit") && p.name.hasPrefix(root.name+" "))))
                }
                if matches.count == 1 {result[p.id]=matches[0].id}
            }
        };cache.identities=identities;cache.owners=result;return result
    }
    func processRows(owners:[Int32:Int32]) -> [Proc] {
        var rows:[Proc]=[]
        let roots=m.processes.filter {$0.app}.sorted(using:sortOrder)
        let visibleIDs=Set(filtered.map(\.id))
        var groups:[(Proc,[Proc])]=[]
        var appRows:[Proc]=[]
        for root in roots {
            let children=m.processes.filter {owners[$0.id] == root.id && $0.id != root.id}.sorted(using:sortOrder)
            guard visibleIDs.contains(root.id) || children.contains(where:{visibleIDs.contains($0.id)}) else {continue}
            var aggregate=root
            for child in children {aggregate.cpu += child.cpu;aggregate.memory += child.memory;aggregate.threads += child.threads;aggregate.diskRead=(aggregate.diskRead ?? 0)+(child.diskRead ?? 0);aggregate.diskWrite=(aggregate.diskWrite ?? 0)+(child.diskWrite ?? 0)}
            if !children.isEmpty {aggregate.name += " (\(children.count+1))"}
            groups.append((aggregate,children.filter {m.query.isEmpty || visibleIDs.contains($0.id)}))
        }
        for aggregate in groups.map({$0.0}).sorted(using:sortOrder) {
            appRows.append(aggregate)
            if expandedApps.contains(aggregate.id) || !m.query.isEmpty {appRows += groups.first(where:{$0.0.id == aggregate.id})!.1}
        }
        let other=filtered.filter {owners[$0.id] == nil}
        if !m.group {return appRows+other}
        for (i,kind) in ["App","Background process","System process"].enumerated() {
            let members=kind == "App" ? appRows : other.filter {$0.kind == kind}
            guard !members.isEmpty else {continue}
            let title=kind == "App" ? "Apps" : kind == "Background process" ? "Background processes" : "System processes"
            rows.append(Proc(id: -Int32(i+1),parent:0,uid:0,name:title,path:kind,cpu:0,memory:0,threads:0,cpuTime:0,diskRead:nil,diskWrite:nil,start:0))
            if !collapsedGroups.contains(kind) {rows += members}
        };return rows
    }
    var processTable:some View {
        GeometryReader {geometry in processTable(width:geometry.size.width)}
    }
    func processTable(width:CGFloat) -> some View {
        let owners=appOwners
        let secondaryWidth:CGFloat = (width >= 880 ? 100 : 0) + (width >= 720 ? 80 : 0) + (width >= 1000 ? 100 : 0)
        let nameWidth=max(180,width-340-secondaryWidth-64)
        return Table(processRows(owners:owners), selection: $m.selected, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { p in
                if p.id < 0 { Button { if collapsedGroups.contains(p.path) { collapsedGroups.remove(p.path) } else { collapsedGroups.insert(p.path) } } label: { HStack { Image(systemName:collapsedGroups.contains(p.path) ? "chevron.right" : "chevron.down").font(.system(size:10)); Text(p.name).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary) } }.buttonStyle(.plain).padding(.vertical,3) }
                else { HStack(spacing:8) {
                    if p.app && owners.contains(where: {$0.key != p.id && $0.value == p.id}) {
                        Button { withAnimation(motion) {if expandedApps.contains(p.id) {expandedApps.remove(p.id)} else {expandedApps.insert(p.id)}} } label: {Image(systemName:"chevron.right").rotationEffect(.degrees(expandedApps.contains(p.id) || !m.query.isEmpty ? 90 : 0)).font(.system(size:10)).frame(width:20,height:24)}.buttonStyle(.plain).accessibilityLabel("\(expandedApps.contains(p.id) || !m.query.isEmpty ? "Collapse" : "Expand") \(p.name)").accessibilityValue(expandedApps.contains(p.id) || !m.query.isEmpty ? "Expanded" : "Collapsed")
                    } else {Color.clear.frame(width:owners[p.id] != nil && !p.app ? 30 : 12,height:1)}
                    Image(nsImage:IconCache.shared.icon(p.path)).resizable().frame(width:19,height:19); Text(p.name).lineLimit(1).truncationMode(.middle).help(p.name) }.contextMenu { processMenu(p) } }
            }.width(min:max(180,nameWidth*0.85),ideal:nameWidth,max:nameWidth)
            if width >= 880 { TableColumn("Status") { p in if p.id > 0 { Text(p.state).foregroundStyle(.secondary) } }.width(min:70,ideal:85,max:100) }
            TableColumn("CPU", value: \.cpu) { p in if p.id > 0 { ResourceCell(value:pct(p.cpu),intensity:p.cpu/25) } }.width(min:65,ideal:80,max:100)
            TableColumn("Memory", value: \.memory) { p in if p.id > 0 { ResourceCell(value:bytes(p.memory),intensity:p.memory/Double(max(1,m.system.memory_total))*8) } }.width(min:85,ideal:105,max:120)
            TableColumn("Disk", value: \.disk) { p in if p.id > 0 { ResourceCell(value:p.diskRead == nil ? "—" : bytes(p.disk)+"/s",intensity:p.disk/10_000_000) } }.width(min:85,ideal:105,max:120)
            if width >= 720 { TableColumn("PID", value: \.id) { p in if p.id > 0 { Text(String(p.id)).foregroundStyle(.secondary).monospacedDigit() } }.width(min:55,ideal:65,max:80) }
            if width >= 1000 { TableColumn("User") { p in if p.id > 0 { Text(p.user).foregroundStyle(.secondary).lineLimit(1) } }.width(min:70,ideal:85,max:100) }
        }.font(.body).tableStyle(.inset).alternatingRowBackgrounds(.enabled)
        .overlay { if filtered.isEmpty { ContentUnavailableView {Label("No matching processes",systemImage:"magnifyingglass")} description: {Text("Try a different name, PID, or user.")} actions: {Button("Clear Search") {m.query="";userFilter=nil}}.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor)) } }
    }
    var detailsTable: some View {
        Table(filtered, selection:$m.selected,sortOrder:$sortOrder) {
            TableColumn("Name",value: \.name) { p in Text(p.name).contextMenu { processMenu(p) } }.width(min:180,ideal:220)
            TableColumn("PID",value: \.id) { Text(String($0.id)).monospacedDigit() }.width(65)
            TableColumn("Status") { Text($0.state).foregroundStyle(.secondary) }.width(80)
            TableColumn("User") { Text($0.user).lineLimit(1) }.width(80)
            TableColumn("CPU",value: \.cpu) { Text(pct($0.cpu)).monospacedDigit() }.width(65)
            TableColumn("CPU time",value: \.cpuTime) { Text(duration($0.cpuTime)).monospacedDigit() }.width(85)
            TableColumn("Memory",value: \.memory) { Text(bytes($0.memory)).monospacedDigit() }.width(100)
            TableColumn("Threads",value: \.threads) { Text(String($0.threads)).monospacedDigit() }.width(60)
            TableColumn("Parent PID",value: \.parent) { Text(String($0.parent)).monospacedDigit() }.width(75)
            TableColumn("Executable") { Text($0.path).lineLimit(1).help($0.path) }.width(min:180,ideal:300)
        }.font(.body).tableStyle(.inset).alternatingRowBackgrounds(.enabled)
    }
    var availableMetrics:[String] { ["CPU","Memory"] + (m.hardware.disks.isEmpty ? [] : m.hardware.disks.enumerated().map { "Disk \($0.offset)" }) + ["Network"] + (m.hardware.gpus.isEmpty ? [] : ["GPU"]) }
    var isDisk:Bool { metric.hasPrefix("Disk") }
    func diskFor(_ title:String) -> DiskCounter? { guard title.hasPrefix("Disk "),let index=Int(title.dropFirst(5)) else {return nil};return m.hardware.disks[safe:index] }
    var selectedDisk:DiskCounter? { diskFor(metric) }
    func metricReading(_ sample:Sample,_ title:String) -> Double { if let disk=diskFor(title) {let rate=sample.disks[disk.id] ?? DiskRate();return rate.read+rate.write};return sample[keyPath:metricKey(title)] }
    var selectedDiskRate:DiskRate { selectedDisk.flatMap {m.diskRates[$0.id]} ?? DiskRate() }
    func metricKey(_ title: String) -> KeyPath<Sample, Double> { switch title { case "Memory": return \.memory; case "Disk": return \.disk; case "Network": return \.network; case "GPU": return \.gpu; default: return \.cpu } }
    func metricColor(_ title:String) -> Color {
        if title.hasPrefix("Disk") {return Color(red:38/255,green:162/255,blue:105/255)}
        switch title {case "Memory":return Color(red:98/255,green:160/255,blue:234/255);case "Network":return Color(red:220/255,green:138/255,blue:221/255);case "GPU":return Color(red:246/255,green:97/255,blue:81/255);default:return Color(red:28/255,green:113/255,blue:216/255)}
    }
    func metricValue(_ title: String) -> String { if let disk=diskFor(title) { let r=m.diskRates[disk.id] ?? DiskRate();return bytes(r.read+r.write)+"/s" };switch title { case "Memory": return "\(bytes(Double(m.system.memory_used))) / \(bytes(Double(m.system.memory_total)))"; case "Disk": return "\(bytes(m.diskRead+m.diskWrite))/s"; case "Network": return "↑ \(rateLabel(m.netOut,network:true))  ↓ \(rateLabel(m.netIn,network:true))"; case "GPU": return pct(m.hardware.gpus.first?.usage ?? 0); default: return pct(m.system.cpu) } }
    var plotEnd: Date { m.samples.last?.date ?? Date() }
    var plotSamples:[Sample] { guard let index=m.samples.firstIndex(where:{$0.date>=plotEnd.addingTimeInterval(-graphDuration)}) else {return m.samples};return Array(m.samples[max(0,index-1)...]) }
    func plotPoints(_ key:KeyPath<Sample,Double>) -> [PlotPoint] { plotSamples.map { PlotPoint(date:$0.date,value:$0[keyPath:key]) } }
    var graphColor:Color { metricColor(metric) }
    var performance: some View {
        GeometryReader { available in
        let below = detailsPosition == "Below" || available.size.width < 920
        let graphHeight=max(260,min(620,available.size.height-(below ? 280 : 150)))
        HStack(alignment:.top,spacing:0) {
            if !m.compact {
                VStack(spacing:7) {
                    ForEach(availableMetrics.filter {m.query.isEmpty || ($0+" "+(diskFor($0)?.name ?? "")).localizedCaseInsensitiveContains(m.query)},id:\.self) { title in
                        Button { withAnimation(motion) {metric=title} } label: {
                            HStack(spacing:12) {
                                if showMiniGraphs { LivePlot(points:plotSamples.map {PlotPoint(date:$0.date,value:metricReading($0,title))},end:plotEnd,seconds:graphDuration,maximum:miniMaximum(title),color:metricColor(title),filled:graphFill,mini:true,valueLabel:{ value in ["CPU","Memory","GPU"].contains(title) ? pct(value) : rateLabel(value,network:title == "Network") },accessibilityName:title).frame(width:80,height:50) }
                                VStack(alignment:.leading,spacing:3) { Text(title).font(.system(size:14,weight:.medium));if let disk=diskFor(title) {Text(disk.name).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1) };Text(metricValue(title)).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2) };Spacer()
                            }.padding(8).background(metric == title ? Color.primary.opacity(0.07) : .clear,in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain).contextMenu { Button("Select \(title)") { metric=title };Toggle("Show mini graphs",isOn:$showMiniGraphs);Toggle("Graph summary view",isOn:$m.compact) }
                    }
                    Spacer()
                }.padding(8).frame(width:242)
                Divider()
            }
            ScrollView {
                HStack(alignment:.top,spacing:16) {
                    VStack(alignment:.leading,spacing:7) {
                        HStack(alignment:.firstTextBaseline) { Text(metric).font(.title2.weight(.semibold));Spacer();Text(hardwareTitle).foregroundStyle(.primary).font(.system(size:13,weight:.semibold)).lineLimit(1) }
                        HStack {
                            Text(metric == "CPU" && cpuGraphMode == "Logical processors" ? "Utilization over \(Int(graphDuration)) seconds" : isDisk || metric == "Network" ? "Transfer rate over \(Int(graphDuration)) seconds" : "Utilization over \(Int(graphDuration)) seconds")
                            Spacer();Text(isDisk || metric == "Network" ? rateLabel(chartMax,network:metric == "Network") : "100%")
                        }.font(.system(size:11)).foregroundStyle(.secondary)
                        performancePlots(height:graphHeight).id(metric).transition(.opacity).contextMenu { graphMenu }.onTapGesture(count:2) { m.compact.toggle() }
                        HStack { Text("\(Int(graphDuration)) seconds");Spacer();Text("0") }.font(.system(size:11)).foregroundStyle(.secondary)
                        if isDisk || metric == "Network" { HStack(spacing:18) { Label(isDisk ? "Read" : "Receive",systemImage:"minus");Label(isDisk ? "Write (dashed)" : "Send (dashed)",systemImage:"ellipsis") }.foregroundStyle(graphColor).font(.system(size:11)) }
                        if !m.compact && below { metricDetails.padding(.top,14) }
                        if !m.compact { performanceSummary.padding(.top,12) }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    if !m.compact && !below { sideDetails.frame(width:210).padding(.top,43) }
                }.padding(m.compact ? 18 : 12).contextMenu { graphMenu }
            }

        }
    }
    }
    @ViewBuilder func performancePlots(height:Double) -> some View {
        if metric == "CPU" && cpuGraphMode == "Logical processors" {
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:7),count:processorColumnCount(Int(m.system.cores))),spacing:7) {
                ForEach(0..<min(128,Int(m.system.cores)),id:\.self) { core in
                    VStack(alignment:.leading,spacing:4) {
                        HStack { Text("CPU \(core)");Spacer();Text(pct(m.samples.last?.coreUsage[safe:core] ?? 0)).monospacedDigit() }.font(.system(size:10)).foregroundStyle(.secondary)
                        LivePlot(points:plotSamples.map { PlotPoint(date:$0.date,value:$0.coreUsage[safe:core] ?? 0) },secondary:showKernelTimes ? plotSamples.map { PlotPoint(date:$0.date,value:$0.coreKernel[safe:core] ?? 0) } : [],end:plotEnd,seconds:graphDuration,maximum:100,color:graphColor,filled:graphFill,animate:!m.paused,accessibilityName:"Logical processor \(core)").frame(height:coreGraphHeight(height)).help("Logical processor \(core)")
                    }
                }
            }
        } else {
            LivePlot(points:isDisk ? plotSamples.map {PlotPoint(date:$0.date,value:$0.disks[selectedDisk?.id ?? 0]?.read ?? 0)} : plotPoints(primaryKey),secondary:secondaryPoints,end:plotEnd,seconds:graphDuration,maximum:chartMax,color:graphColor,filled:graphFill,animate:!m.paused,valueLabel:{value in if metric == "Memory" {return pct(value)+" • "+bytes(value/100*Double(m.system.memory_total))};if metric == "Network" {return rateLabel(value,network:true)};if isDisk {return bytes(value)+"/s"};return pct(value)},secondaryLabel:metric == "Network" ? "Send" : isDisk ? "Write" : "Kernel",accessibilityName:metric).frame(height:m.compact ? 240 : height)
        }
    }
    func coreGraphHeight(_ height:Double) -> Double { let rows=ceil(Double(m.system.cores)/Double(processorColumnCount(Int(m.system.cores))));return max(65,(height-25*rows)/rows) }
    @ViewBuilder var sideDetails: some View {
        VStack(alignment:.leading,spacing:14) {
            if metric == "CPU" {
                sideStat("Utilization",pct(m.system.cpu))
                HStack(spacing:20) {sideStat("Processes",String(m.processes.count));sideStat("Threads",String(m.processes.reduce(0){$0+$1.threads}))}
                sideStat("Up time",duration(ProcessInfo.processInfo.systemUptime))
                Divider().padding(.vertical,3)
                sideLine("User",pct(max(0,m.system.cpu-m.system.kernel)));sideLine("System",pct(m.system.kernel));sideLine("Idle",pct(max(0,100-m.system.cpu)));sideLine("Logical processors",String(m.system.cores));sideLine("Physical cores",sysctlNumber("hw.physicalcpu"));sideLine("Architecture", "Apple silicon")
                Text(ProcessInfo.processInfo.operatingSystemVersionString).font(.system(size:11)).foregroundStyle(.secondary)
            } else if metric == "Memory" {sideStat("In use",bytes(Double(m.system.memory_used)));sideStat("Compressed",bytes(Double(m.system.compressed)));sideStat("Swap used",bytes(Double(m.system.swap_used)));Divider();sideLine("Physical memory",bytes(Double(m.system.memory_total)));memoryBreakdown}
            else if isDisk {sideStat("Read speed",bytes(selectedDiskRate.read)+"/s");sideStat("Write speed",bytes(selectedDiskRate.write)+"/s");Divider();if let disk=selectedDisk {sideLine("Device",disk.bsd.isEmpty ? "Storage" : disk.bsd);sideLine("Capacity",bytes(disk.capacity));sideLine("Read total",bytes(disk.read));sideLine("Write total",bytes(disk.write));Text("Device counters since attachment or reset").font(.caption).foregroundStyle(.secondary);Text(disk.name).font(.system(size:11)).foregroundStyle(.secondary)}}
            else if metric == "Network" {sideStat("Send",rateLabel(m.netOut,network:true));sideStat("Receive",rateLabel(m.netIn,network:true));Divider();sideLine("Received total",bytes(Double(m.system.net_in)));sideLine("Sent total",bytes(Double(m.system.net_out)));Text("Wi-Fi and Ethernet interfaces combined; totals since interface reset").font(.caption).foregroundStyle(.secondary)}
            else {sideStat("Utilization",pct(m.hardware.gpus.first?.usage ?? 0));if let r=m.hardware.gpus.first?.render {sideStat("Renderer",pct(r))};if let t=m.hardware.gpus.first?.tiler {sideStat("Tiler",pct(t))};Divider();sideLine("Memory", "Shared unified memory");Text("Renderer measures rendering work; tiler prepares geometry for rendering. Values are reported by the GPU driver.").font(.caption).foregroundStyle(.secondary)}
            Spacer(minLength:0)
        }
    }
    var memoryBreakdown:some View { VStack(alignment:.leading,spacing:8) {sideLine("Active",bytes(Double(m.system.memory_active)));sideLine("Wired",bytes(Double(m.system.memory_wired)));sideLine("Cached files",bytes(Double(m.system.memory_cached)));sideLine("Free + speculative",bytes(Double(m.system.memory_free)));sideLine("Swap allocated",bytes(Double(m.system.swap_total)))} }
    var performanceSummary:some View {
        let values=plotSamples.filter {$0.date >= plotEnd.addingTimeInterval(-graphDuration)}.map {metricReading($0,metric)}
        let average=values.isEmpty ? 0 : values.reduce(0,+)/Double(values.count)
        return VStack(alignment:.leading,spacing:10) {
            Divider()
            HStack(spacing:28) {sideStat("Average",summaryValue(average));sideStat("Peak",summaryValue(values.max() ?? 0));sideStat("Sample interval",String(format:"%g s",m.interval))}
            Text("Average and peak over the recorded portion of the last \(Int(graphDuration)) seconds. Disk and network summaries combine both transfer directions.").font(.caption).foregroundStyle(.secondary)
        }
    }
    func summaryValue(_ value:Double) -> String {isDisk ? bytes(value)+"/s" : metric == "Network" ? rateLabel(value,network:true) : pct(value)}
    func sideStat(_ title:String,_ value:String) -> some View {VStack(alignment:.leading,spacing:4) {Text(title).font(.system(size:11)).foregroundStyle(.secondary);Reading(value:value).font(.system(size:18,weight:.semibold))}}
    func sideLine(_ title:String,_ value:String) -> some View {HStack(alignment:.top) {Text(title).foregroundStyle(.secondary);Spacer();Text(value).monospacedDigit()}.font(.system(size:11))}
    var primaryKey:KeyPath<Sample,Double> { isDisk ? \.read : metric == "Network" ? \.receive : metricKey(metric) }
    var secondaryPoints:[PlotPoint] { if metric == "CPU" && showKernelTimes { return plotPoints(\.kernel) };if metric == "Network" { return plotPoints(\.send) };if isDisk { return plotSamples.map {PlotPoint(date:$0.date,value:$0.disks[selectedDisk?.id ?? 0]?.write ?? 0)} };return [] }
    @ViewBuilder var graphMenu: some View {
        if metric == "CPU" {
            Menu("Change graph to") { Picker("CPU graph",selection:$cpuGraphMode) { Text("Overall utilization").tag("Overall utilization");Text("Logical processors").tag("Logical processors") }.pickerStyle(.inline) }
            Toggle("Show kernel times",isOn:$showKernelTimes)
            Divider()
        }
        Toggle("Graph summary view",isOn:$m.compact)
        Toggle("Smooth graphs",isOn:$smoothGraphs)
        Toggle("Sliding graphs",isOn:$slidingGraphs)
        Toggle("Fill graph area",isOn:$graphFill)
        Toggle("Show mini graphs",isOn:$showMiniGraphs)
        Menu("View") { ForEach(availableMetrics,id:\.self) { title in Button(title) { metric=title } } }
        Menu("Update speed") { Button("Fast — 0.5 seconds") {m.interval=0.5;m.restartTimer()}; Button("High — 1 second") { m.interval=1;m.restartTimer() };Button("Normal — 2 seconds") { m.interval=2;m.restartTimer() };Button("Low — 4 seconds") { m.interval=4;m.restartTimer() };Toggle("Paused",isOn:$m.paused) }
        Divider()
        Button("Copy") { NSPasteboard.general.clearContents();NSPasteboard.general.setString("\(metric)\n\(hardwareTitle)\n\(metricValue(metric))\nLogical processors: \(m.system.cores)\nProcesses: \(m.processes.count)\nUp time: \(duration(ProcessInfo.processInfo.systemUptime))",forType:.string) }
    }
    func miniMaximum(_ title:String) -> Double { if ["CPU","Memory","GPU"].contains(title) { return 100 };return niceMaximum(plotSamples.map { metricReading($0,title) }.max() ?? 0) }
    var chartMax:Double { if ["CPU","Memory","GPU"].contains(metric) { return 100 };return niceMaximum(plotSamples.map { s in if isDisk {let r=s.disks[selectedDisk?.id ?? 0] ?? DiskRate();return max(r.read,r.write)};return max(s[keyPath:primaryKey],s.send) }.max() ?? 0) }
    func niceMaximum(_ value:Double) -> Double { let value=max(1024,value*1.1);let power=pow(10,floor(log10(value)));let unit=value/power;return (unit<=1 ? 1 : unit<=2 ? 2 : unit<=5 ? 5 : 10)*power }
    func rateLabel(_ value:Double,network:Bool) -> String { if network && networkBits { let bits=value*8;if bits>=1e9 { return String(format:"%.1f Gbps",bits/1e9) };if bits>=1e6 { return String(format:"%.1f Mbps",bits/1e6) };return String(format:"%.1f Kbps",bits/1e3) };return bytes(value)+"/s" }
    var hardwareTitle: String { if let disk=selectedDisk {return disk.name};switch metric { case "CPU": return sysctlString("machdep.cpu.brand_string"); case "Memory": return "Unified / physical memory"; case "GPU": return m.hardware.gpus.first?.name ?? "GPU"; case "Disk": return "\(m.hardware.disks.count) physical disk(s)"; default: return "Wi-Fi and Ethernet interfaces" } }
    @ViewBuilder var metricDetails: some View {
        if metric == "CPU" {
            HStack(alignment: .top, spacing: 40) { stat("Utilization", pct(m.system.cpu)); stat("Processes", String(m.processes.count)); stat("Threads", String(m.processes.reduce(0){$0+$1.threads})) }
            detail("User / System / Idle", "\(pct(max(0,m.system.cpu-m.system.kernel))) / \(pct(m.system.kernel)) / \(pct(max(0,100-m.system.cpu)))");detail("Physical cores",sysctlNumber("hw.physicalcpu"));detail("Logical processors", String(m.system.cores)); detail("Up time", duration(ProcessInfo.processInfo.systemUptime)); detail("Operating system", ProcessInfo.processInfo.operatingSystemVersionString)
        } else if metric == "Memory" {
            HStack(spacing: 35) { stat("In use", bytes(Double(m.system.memory_used))); stat("Compressed", bytes(Double(m.system.compressed))); stat("Swap used", bytes(Double(m.system.swap_used))) }
            detail("Physical memory", bytes(Double(m.system.memory_total)));memoryBreakdown; Text("In use excludes reclaimable file cache and purgeable memory. Memory categories can overlap and should not be added together.").font(.system(size: 11)).foregroundStyle(.secondary)
        } else if isDisk {
            HStack(spacing: 45) { stat("Read speed",bytes(selectedDiskRate.read)+"/s");stat("Write speed",bytes(selectedDiskRate.write)+"/s") }
            if let disk=selectedDisk { detail("Device",disk.bsd.isEmpty ? "Physical storage device" : "/dev/"+disk.bsd);detail("Capacity",bytes(disk.capacity));detail("Read total",bytes(disk.read));detail("Write total",bytes(disk.write));Text("Device totals since attachment or counter reset.").font(.caption).foregroundStyle(.secondary) }
            if m.hardware.disks.isEmpty { Text("This Mac does not expose physical disk counters. Process disk activity is available in Processes.").foregroundStyle(.secondary) }
        } else if metric == "Network" { HStack(spacing: 45) { stat("Send", rateLabel(m.netOut,network:true)); stat("Receive", rateLabel(m.netIn,network:true)) }; detail("Scope", "Wi-Fi and Ethernet interfaces combined");detail("Received total",bytes(Double(m.system.net_in)));detail("Sent total",bytes(Double(m.system.net_out))) }
        else { HStack(spacing: 45) { stat("GPU utilization", pct(m.hardware.gpus.first?.usage ?? 0)); if let render = m.hardware.gpus.first?.render { stat("Renderer", pct(render)) }; if let tiler = m.hardware.gpus.first?.tiler { stat("Tiler", pct(tiler)) } }; detail("Source", "IOKit accelerator statistics") }
    }
    func stat(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 7) { Text(label).font(.system(size: 12)).foregroundStyle(.secondary); Reading(value:value).font(.system(size: 25, weight: .regular)) } }
    func detail(_ label: String, _ value: String) -> some View { HStack { Text(label).foregroundStyle(.secondary).frame(width: 140, alignment: .leading); Text(value) }.font(.system(size: 12)) }
    var historyTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Resource usage recorded while Houston is running, since \(m.historySince.formatted()).").font(.system(size: 12)).foregroundStyle(.secondary).padding(20)
            Table(m.history.filter { m.query.isEmpty || $0.name.localizedCaseInsensitiveContains(m.query) }, selection: $historySelection) {
                TableColumn("Name") { Text($0.name) }.width(min: 200, ideal: 300)
                TableColumn("CPU time") { Text(duration($0.cpu)).monospacedDigit() }
                TableColumn("Disk read") { ResourceCell(value: bytes($0.read), intensity: $0.read/1e9) }
                TableColumn("Disk write") { ResourceCell(value: bytes($0.write), intensity: $0.write/1e9) }
                TableColumn("Last seen") { Text($0.lastSeen.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
            }.font(.system(size: 12))
        }
    }
    var startupTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Installed launch agents and daemons. Manage app login and background permissions in Login Items.").font(.system(size: 12)).foregroundStyle(.secondary).padding(20)
            Table(m.startup.filter { m.query.isEmpty || $0.name.localizedCaseInsensitiveContains(m.query) }, selection: $startupSelection) {
                TableColumn("Name") { r in Text(r.name).contextMenu { Button("Open configuration location") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:r.path)]) }; Button("Manage Login Items…") { m.openLoginItems() } } }.width(min: 240, ideal: 330)
                TableColumn("Scope") { Text($0.scope) }
                TableColumn("Trigger") { Text($0.trigger) }
                TableColumn("Job status") { r in Text(m.services.first(where:{$0.id == r.name})?.status ?? "Not loaded in user session").foregroundStyle(.secondary) }
            }.font(.system(size: 12))
        }
    }
    var usersTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Process owners on this Mac. Memory totals count shared pages in each process.").font(.system(size: 12)).foregroundStyle(.secondary).padding(20)
            Table(m.users.filter { m.query.isEmpty || $0.name.localizedCaseInsensitiveContains(m.query) }, selection: $userSelection) {
                TableColumn("User") { u in Label(u.name, systemImage: "person.circle").contextMenu { Button("Show processes") { m.page = .details; userFilter = u.id } } }.width(min: 180, ideal: 280)
                TableColumn("UID") { Text(String($0.id)) }
                TableColumn("Processes") { Text(String($0.count)) }
                TableColumn("CPU") { ResourceCell(value: pct($0.cpu), intensity: $0.cpu/100) }
                TableColumn("Memory") { ResourceCell(value: bytes($0.memory), intensity: $0.memory/Double(max(1,m.system.memory_total))) }
            }.font(.system(size: 12))
        }
    }
    var servicesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("launchd jobs in your current user session").font(.system(size:12)).foregroundStyle(.secondary);Spacer();Picker("Filter",selection:$serviceFilter) {Text("All").tag("All");Text("Running").tag("Running");Text("Stopped").tag("Stopped")}.pickerStyle(.segmented).frame(width:260) }.padding(20)
            Table(m.services.filter { (m.query.isEmpty || $0.id.localizedCaseInsensitiveContains(m.query)) && (serviceFilter == "All" || $0.status == serviceFilter) }, selection: $serviceSelection) {
                TableColumn("Name") { r in Text(r.id).contextMenu { Button("Start / restart") { m.serviceAction("Start", r) }; Button("Stop") { m.serviceAction("Stop", r) }.disabled(r.pid == "-"); if !r.path.isEmpty { Button("Open configuration location") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:r.path)]) } } } }.width(min: 260, ideal: 400)
                TableColumn("PID") { Text($0.pid).monospacedDigit() }.width(65)
                TableColumn("Status") { r in Label(r.status, systemImage:r.status == "Running" ? "circle.fill" : "circle").foregroundStyle(r.status == "Running" ? .green : .secondary).font(.system(size: 11)) }
                TableColumn("Last exit code") { Text($0.exit).monospacedDigit() }
                TableColumn("Scope") { Text($0.scope).foregroundStyle(.secondary) }
            }.font(.system(size: 12))
        }
    }
}
extension Array { subscript(safe index:Int) -> Element? { indices.contains(index) ? self[index] : nil } }
func duration(_ seconds: Double) -> String { let s = Int(max(0,seconds)); return String(format: "%d:%02d:%02d", s/3600, (s/60)%60, s%60) }
func sysctlNumber(_ key:String) -> String { var value:Int32=0;var size=MemoryLayout<Int32>.size;return sysctlbyname(key,&value,&size,nil,0)==0 ? String(value) : "Unavailable" }
func sysctlString(_ key: String) -> String { var size = 0; sysctlbyname(key,nil,&size,nil,0); guard size>0 else { return "Apple processor" }; var buffer = [CChar](repeating:0,count:size); sysctlbyname(key,&buffer,&size,nil,0); return String(cString:buffer) }
struct Reading:View {
    var value:String
    var body:some View {Text(value).monospacedDigit().transaction {$0.animation=nil}}
}
@MainActor func showAbout() {
    let info=Bundle.main.infoDictionary ?? [:]
    let credits=NSMutableAttributedString(string:"Mission control for your Mac.\n\nLive processes, performance graphs, and optional menu-bar monitors. Readings and recorded history stay on this Mac.\n\nHouston is free software under GPL-3.0-or-later, supplied without warranty. The complete license and corresponding source accompany each release.\n\nOpen-source credits\nMission Center UI reference — GPL-3.0-or-later\nStats monitoring reference — MIT\nSparkle updater — MIT (additional bundled notices)\n\nAI usage disclosure\nDeveloped with substantial assistance from OpenAI Codex for code, design, debugging, tests, and documentation. No endorsement or accuracy guarantee is implied.\n\n",attributes:[.font:NSFont.systemFont(ofSize:12),.foregroundColor:NSColor.labelColor])
    for (name,address) in [("Mission Center","https://gitlab.com/mission-center-devs/mission-center"),("Stats","https://github.com/exelban/stats"),("Graph widget","https://gitlab.com/mission-center-devs/graph-widget"),("Sparkle","https://github.com/sparkle-project/Sparkle")] {
        credits.append(NSAttributedString(string:name+"\n",attributes:[.link:URL(string:address)!, .font:NSFont.systemFont(ofSize:12)]))
    }
    if let license=Bundle.main.url(forResource:"LICENSE",withExtension:nil) {credits.append(NSAttributedString(string:"License\n",attributes:[.link:license,.font:NSFont.systemFont(ofSize:12)]))}
    for name in ["THIRD-PARTY-NOTICES.md", "AI_DISCLOSURE.md", "SPARKLE-LICENSE.txt"] { if let url=Bundle.main.url(forResource:name,withExtension:nil) {credits.append(NSAttributedString(string:name+"\n",attributes:[.link:url,.font:NSFont.systemFont(ofSize:12)]))} }
    NSApp.activate(ignoringOtherApps:true)
    NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Houston",.applicationVersion:info["CFBundleShortVersionString"] as? String ?? "1.3",.version:info["CFBundleVersion"] as? String ?? "4",.credits:credits])
}
struct SettingsContent: View {
    @EnvironmentObject var m:Monitor
    @AppStorage("appearance") var appearance="System"
    @AppStorage("runInBackground") var runInBackground=true
    @AppStorage("showMenuBar") var showMenuBar=true
    @AppStorage("menuMemory") var menuMemory=false
    @AppStorage("menuGPU") var menuGPU=false
    @AppStorage("menuDisk") var menuDisk=false
    @AppStorage("menuNetwork") var menuNetwork=false
    @AppStorage("menuValues") var menuValues=true
    @AppStorage("grayZeroes") var grayZeroes=true
    @AppStorage("normalizeCPU") var normalizeCPU=true
    @AppStorage("detailsPosition") var detailsPosition="Right"
    @AppStorage("defaultPage") var defaultPage="Processes"
    @AppStorage("graphDuration") var graphDuration=60.0
    @AppStorage("smoothGraphs") var smoothGraphs=false
    @AppStorage("slidingGraphs") var slidingGraphs=true
    @AppStorage("graphFill") var graphFill=true
    @AppStorage("showMiniGraphs") var showMiniGraphs=true
    @AppStorage("cpuGraphMode") var cpuGraphMode="Overall utilization"
    @AppStorage("showKernelTimes") var showKernelTimes=false
    @AppStorage("networkBits") var networkBits=true
    @AppStorage("animations") var animations=true
    var body:some View {
        TabView {
            Form {
                Section("Appearance") {
                    Picker("Appearance",selection:$appearance) {Text("System").tag("System");Text("Light").tag("Light");Text("Dark").tag("Dark")}
                    Toggle("Keep window on top",isOn:$m.alwaysOnTop)
                    Toggle("Animate navigation and graphs",isOn:$animations)
                    Text("Animations follow the macOS Reduce Motion setting.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Window") {Picker("Open to",selection:$defaultPage) {ForEach(Page.allCases.filter {$0 != .settings}) {Text($0.rawValue).tag($0.rawValue)}};Toggle("Keep monitoring when the window is closed",isOn:$runInBackground);Text("Menu-bar gadgets keep updating in the background. Choose Quit Houston to stop monitoring.").font(.caption).foregroundStyle(.secondary)}
                Section {Button("About Houston…") {showAbout()}}
            }.formStyle(.grouped).tabItem {Label("General",systemImage:"gearshape")}
            Form {
                Section("Sampling") {Picker("Update interval",selection:$m.interval) {Text("0.5 seconds").tag(0.5);Text("1 second").tag(1.0);Text("2 seconds").tag(2.0);Text("4 seconds").tag(4.0)}.onChange(of:m.interval) {_,_ in m.restartTimer()};Toggle("Pause updates",isOn:$m.paused)}
                Section("Graphs") {
                    Picker("History",selection:$graphDuration) {Text("30 seconds").tag(30.0);Text("60 seconds").tag(60.0);Text("2 minutes").tag(120.0);Text("5 minutes").tag(300.0)}
                    Picker("CPU graph",selection:$cpuGraphMode) {Text("Overall utilization").tag("Overall utilization");Text("Logical processors").tag("Logical processors")}
                    Toggle("Show kernel times",isOn:$showKernelTimes)
                    Toggle("Smooth curves",isOn:$smoothGraphs);Toggle("Scroll graphs continuously",isOn:$slidingGraphs);Toggle("Fill graph area",isOn:$graphFill);Toggle("Show miniature graphs",isOn:$showMiniGraphs)
                    Toggle("Network rates in bits per second",isOn:$networkBits)
                    Picker("Statistics",selection:$detailsPosition) {Text("Right of graph").tag("Right");Text("Below graph").tag("Below")}
                    Text("Statistics move below graphs automatically in narrow windows. Right-click graphs for more options.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem {Label("Monitoring",systemImage:"waveform.path.ecg")}
            Form {
                Section("Menu-bar gadget") {
                    Toggle("CPU",isOn:$showMenuBar)
Toggle("Memory",isOn:$menuMemory)
Toggle("GPU",isOn:$menuGPU)
Toggle("Disk activity",isOn:$menuDisk)
Toggle("Network",isOn:$menuNetwork)
                    Toggle("Show values beside icons",isOn:$menuValues)
                    Text("Selected statistics appear together in one gadget. Click it to see all readings and graphs. It keeps updating while the window is closed. GPU readings require driver support.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem {Label("Menu Bar",systemImage:"menubar.rectangle")}
            Form {
                Section("Processes") {Toggle("Group by process type",isOn:$m.group);Toggle("Scale CPU usage to core count",isOn:$normalizeCPU);Toggle("Dim zero readings",isOn:$grayZeroes)}
                Section("Local data") {
                    Text("Monitoring and usage history stay on this Mac. No account or telemetry is required.")
                    Button("Export Process List…") {m.export()}
                    Button("Delete Recorded History…",role:.destructive) {m.clearHistory()}
                }
                Section("Credits") {Text("Houston is distributed under GPL-3.0-or-later. See About Houston for acknowledgements and the bundled license.").font(.caption).foregroundStyle(.secondary);Button("About Houston…") {showAbout()}}
            }.formStyle(.grouped).tabItem {Label("Data",systemImage:"externaldrive")}
            UpdateSettings().tabItem {Label("Updates",systemImage:"arrow.down.circle")}
        }.padding(12)
    }
}
@MainActor enum Gadget:String,Identifiable {
    nonisolated var id:String {rawValue}
    case cpu="CPU", memory="Memory", gpu="GPU", disk="Disk activity", network="Network"
    var symbol:String {switch self {case .cpu:return "cpu";case .memory:return "memorychip";case .gpu:return "rectangle.3.group";case .disk:return "internaldrive";case .network:return "network"}}
    var key:KeyPath<Sample,Double> {switch self {case .cpu:return \.cpu;case .memory:return \.memory;case .gpu:return \.gpu;case .disk:return \.disk;case .network:return \.network}}
    var color:Color {switch self {case .cpu:return .blue;case .memory:return .purple;case .gpu:return .orange;case .disk:return .green;case .network:return .teal}}
    func value(_ m:Monitor) -> Double {switch self {case .cpu:return m.system.cpu;case .memory:return Double(m.system.memory_used)/Double(max(1,m.system.memory_total))*100;case .gpu:return m.hardware.gpus.first?.usage ?? 0;case .disk:return m.diskRead+m.diskWrite;case .network:return m.netIn+m.netOut}}
    func label(_ v:Double) -> String {self == .disk || self == .network ? bytes(v)+"/s" : pct(v)}
}
@MainActor final class StatusGadgets:NSObject,NSPopoverDelegate {
    unowned let monitor:Monitor
    var strip:NSStatusItem?
    var popover:NSPopover?
    var observers:Set<AnyCancellable>=[]
    var updatePending=false
    var symbols:[Gadget:NSImage]=[:]
    var lastSignature=""
    static let configurations:[(Gadget,String,Bool)] = [(.cpu,"showMenuBar",true),(.memory,"menuMemory",false),(.gpu,"menuGPU",false),(.disk,"menuDisk",false),(.network,"menuNetwork",false)]
    static func enabledKinds() -> [Gadget] {
        configurations.compactMap {kind,key,fallback in
            (UserDefaults.standard.object(forKey:key) as? Bool ?? fallback) ? kind : nil
        }
    }
    init(monitor:Monitor) {
        self.monitor=monitor;super.init()
        monitor.objectWillChange.sink {[weak self] _ in self?.scheduleUpdate()}.store(in:&observers)
        NotificationCenter.default.publisher(for:UserDefaults.didChangeNotification).sink {[weak self] _ in self?.scheduleUpdate()}.store(in:&observers)
        update()
    }
    func scheduleUpdate() {
        guard !updatePending else {return};updatePending=true
        DispatchQueue.main.async {[weak self] in guard let self else {return};self.updatePending=false;self.update()}
    }
    func update() {
        let kinds=Self.enabledKinds()
        guard !kinds.isEmpty else {
            popover?.close();popover=nil
            if let strip {NSStatusBar.system.removeStatusItem(strip)};strip=nil;lastSignature="";return
        }
        if strip == nil {
            let item=NSStatusBar.system.statusItem(withLength:24);item.autosaveName="Houston.Gadgets"
            item.button?.target=self;item.button?.action=#selector(clicked(_:))
            item.button?.imagePosition = .imageOnly;item.button?.imageScaling = .scaleNone
            strip=item
        }
        let showValues=UserDefaults.standard.object(forKey:"menuValues") as? Bool ?? true
        var x:CGFloat=1
        var entries:[(NSImage?,String,CGFloat)]=[]
        var fullValues:[String]=[]
        for kind in kinds {
            if symbols[kind] == nil {symbols[kind]=NSImage(systemSymbolName:kind.symbol,accessibilityDescription:kind.rawValue)?.withSymbolConfiguration(.init(pointSize:12,weight:.regular))}
            let missing=kind == .gpu && monitor.hardware.gpus.isEmpty
            let value=kind.value(monitor),rate=kind == .disk || kind == .network
            let label=showValues ? (missing ? "—" : rate ? menuRate(value) : String(format:"%.0f%%",min(100,max(0,value)))) : ""
            entries.append((symbols[kind],label,x))
            fullValues.append(kind.rawValue+" "+(missing ? "Unavailable" : kind.label(value)))
            x += showValues ? ceil(12+3+(rate ? MenuGadgetGeometry.rateWidth : MenuGadgetGeometry.percentWidth))+2 : 16
        }
        let width=x-2,signature=kinds.map {$0.rawValue}.joined()+entries.map {$0.1}.joined()+String(showValues)
        if strip?.length != width+4 {strip?.length=width+4}
        if signature != lastSignature {
            lastSignature=signature
            let font=MenuGadgetGeometry.font
            let rendered=NSImage(size:NSSize(width:width,height:18),flipped:false) {rect in
                NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:rect).addClip()
                for (symbol,label,x) in entries {
                    if let symbol {
                        let scale=min(12/max(1,symbol.size.width),12/max(1,symbol.size.height))
                        let size=NSSize(width:symbol.size.width*scale,height:symbol.size.height*scale)
                        symbol.draw(in:NSRect(x:x+(12-size.width)/2,y:(18-size.height)/2,width:size.width,height:size.height))
                    }
                    if !label.isEmpty {
                        let attributes:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:NSColor.black]
                        let size=(label as NSString).size(withAttributes:attributes)
                        (label as NSString).draw(at:NSPoint(x:x+15,y:(18-size.height)/2),withAttributes:attributes)
                    }
                }
                NSGraphicsContext.restoreGraphicsState();return true
            }
            rendered.isTemplate=true;strip?.button?.image=rendered
        }
        let description="Houston • "+fullValues.joined(separator:" • ")
        strip?.button?.toolTip="Show Houston statistics";strip?.button?.setAccessibilityLabel(description)
    }
    func popoverShouldDetach(_ popover:NSPopover) -> Bool {true}
    func popoverDidDetach(_ popover:NSPopover) {
        NotificationCenter.default.post(name:Notification.Name("HoustonGadgetDetached"),object:nil)
        guard let window=popover.contentViewController?.view.window else {return}
        window.title="Houston"
        window.titleVisibility = .visible
        window.isMovableByWindowBackground=true
        window.level = .floating
        window.setFrameAutosaveName("HoustonStatistics")
    }
    @objc func clicked(_ sender:NSStatusBarButton) {show()}
    func show() {
        guard let button=strip?.button else {return}
        if let popover,popover.isDetached {popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil);return}
        if let popover,popover.isShown {popover.close();return}
        let panel=NSPopover();panel.behavior = .transient;panel.delegate=self
        panel.animates = (UserDefaults.standard.object(forKey:"animations") as? Bool ?? true) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.contentViewController=NSHostingController(rootView:GadgetPanel(m:monitor));panel.contentViewController?.title="Houston"
        popover=panel;NSApp.activate(ignoringOtherApps:true);panel.show(relativeTo:button.bounds,of:button,preferredEdge:.minY);panel.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }
}
private struct GadgetContentHeight:PreferenceKey {
    static let defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=max(value,nextValue())}
}
struct GadgetPanel:View {
    @ObservedObject var m:Monitor
    @AppStorage("appearance") var appearance="System"
    @State private var detached=false
    @State private var kinds=StatusGadgets.enabledKinds()
    @State private var contentHeight:CGFloat=450
    var samples:[Sample] {m.samples.filter {$0.date >= (m.samples.last?.date ?? Date()).addingTimeInterval(-60)}}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            if !detached {HStack {Text("Houston").font(.headline);Spacer();Text(m.paused ? "Paused" : "Live").font(.caption).foregroundStyle(.secondary)}}
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(kinds,id:\.self) {kind in
                        HStack(alignment:.center,spacing:16) {
                            VStack(alignment:.leading,spacing:4) {
                                Label(kind.rawValue,systemImage:kind.symbol).font(.caption).foregroundStyle(.secondary)
                                Reading(value:kind == .gpu && m.hardware.gpus.isEmpty ? "Unavailable" : kind == .memory ? bytes(Double(m.system.memory_used))+" / "+bytes(Double(m.system.memory_total)) : kind.label(kind.value(m))).font(.title3.weight(.medium)).monospacedDigit()
                                Text(detail(kind)).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            if kind != .gpu || !m.hardware.gpus.isEmpty {
                                LivePlot(points:samples.map {PlotPoint(date:$0.date,value:$0[keyPath:kind.key])},end:samples.last?.date ?? Date(),seconds:60,maximum:kind == .network || kind == .disk ? max(1024,(samples.map {$0[keyPath:kind.key]}.max() ?? 0)*1.1) : 100,color:kind.color,filled:true,mini:true,animate:false,valueLabel:{kind.label($0)},accessibilityName:kind.rawValue).frame(width:108,height:44)
                            }
                        }.padding(.vertical,2)
                        if kind != kinds.last {Divider()}
                    }
                }.padding(.trailing,2)
                .background(GeometryReader {geometry in Color.clear.preference(key:GadgetContentHeight.self,value:geometry.size.height)})
            }.frame(height:min(480,contentHeight))
            .onPreferenceChange(GadgetContentHeight.self) {height in if height > 0 {contentHeight=height}}
            HStack {Text("Last 60 seconds • Updated every \(m.interval, specifier:"%g") s");if detached {Spacer();Text(m.paused ? "Paused" : "Live")}}.font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Open Houston") {m.page = .performance;m.openMainWindow?()}
                Spacer()
                Button {m.paused.toggle()} label: {Image(systemName:m.paused ? "play.fill" : "pause.fill")}.help(m.paused ? "Resume monitoring" : "Pause monitoring")
                Button {m.openSettingsWindow?()} label: {Image(systemName:"gearshape")}.help("Settings…")
            }
        }.padding(16).frame(width:360).preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
        .onReceive(NotificationCenter.default.publisher(for:Notification.Name("HoustonGadgetDetached"))) {_ in detached=true}
        .onReceive(NotificationCenter.default.publisher(for:UserDefaults.didChangeNotification)) {_ in kinds=StatusGadgets.enabledKinds()}
    }
    func detail(_ kind:Gadget) -> String {
        switch kind {
        case .cpu:return "System "+pct(m.system.kernel)+" • "+String(m.processes.count)+" processes"
        case .memory:return pct(Double(m.system.memory_used)/Double(max(1,m.system.memory_total))*100)+" used • Compressed "+bytes(Double(m.system.compressed))
        case .gpu:return m.hardware.gpus.first?.name ?? "No GPU counters available"
        case .disk:return "Read "+bytes(m.diskRead)+"/s • Write "+bytes(m.diskWrite)+"/s"
        case .network:return "Receive "+bytes(m.netIn)+"/s • Send "+bytes(m.netOut)+"/s"
        }
    }
}
struct Inspector: View {
    var proc: Proc
    @EnvironmentObject var m: Monitor
    @Environment(\.dismiss) var dismiss
    var current: Proc { m.processes.first { $0.id == proc.id && $0.start == proc.start } ?? proc }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Image(nsImage:IconCache.shared.icon(proc.path)).resizable().frame(width:40,height:40); VStack(alignment:.leading) { Text(proc.name).font(.title2); Text("PID \(proc.id) • \(proc.user)").foregroundStyle(.secondary) }; Spacer(); Button("Done") { dismiss() } }
            Grid(alignment:.leading,horizontalSpacing:30,verticalSpacing:12) {
                GridRow { Text("CPU").foregroundStyle(.secondary); Text(pct(current.cpu)) }; GridRow { Text("Memory").foregroundStyle(.secondary); Text(bytes(current.memory)) }; GridRow { Text("CPU time").foregroundStyle(.secondary); Text(duration(current.cpuTime)) }; GridRow { Text("Threads").foregroundStyle(.secondary); Text(String(current.threads)) }; GridRow { Text("Parent PID").foregroundStyle(.secondary); Text(String(current.parent)) }; GridRow { Text("Started").foregroundStyle(.secondary); Text(Date(timeIntervalSince1970:Double(current.start)).formatted()) }
            }
            Text(proc.path.isEmpty ? "Executable path unavailable" : proc.path).font(.system(size:12,design:.monospaced)).textSelection(.enabled).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
            HStack { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:proc.path)]) }.disabled(proc.path.isEmpty); Spacer(); Button("End task") { m.processAction("End task",proc:proc) }.disabled(!m.canControl(proc)) }
        }.padding(25).frame(width:540)
    }
}
@MainActor final class HoustonAppDelegate:NSObject,NSApplicationDelegate {
    var reopenWindow:(()->Void)?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool {
        UserDefaults.standard.object(forKey:"runInBackground") as? Bool == false
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows visible:Bool) -> Bool {
        if !visible {reopenWindow?()};return true
    }
}
@main struct TaskManagerApp: App {
    @NSApplicationDelegateAdaptor(HoustonAppDelegate.self) var delegate
    @StateObject var monitor = Monitor()
    @AppStorage("showMenuBar") var showMenuBar = true
    @AppStorage("menuMemory") var menuMemory=false
    @AppStorage("menuGPU") var menuGPU=false
    @AppStorage("menuDisk") var menuDisk=false
    @AppStorage("menuNetwork") var menuNetwork=false
    @AppStorage("appearance") var appearance = "System"
    var body: some Scene {
        Window("Houston", id:"main") { MainView().environmentObject(monitor).onAppear { _ = HoustonUpdater.shared; delegate.reopenWindow={monitor.openMainWindow?()}; NSApp.setActivationPolicy(.regular);if let url=Bundle.main.url(forResource:"TaskManager",withExtension:"icns"),let icon=NSImage(contentsOf:url) {NSApp.applicationIconImage=icon}; NSApp.activate(ignoringOtherApps:true) } }.defaultSize(width:1250,height:790).windowToolbarStyle(.unified)
        .commands { TaskCommands(monitor:monitor) }
        Settings { SettingsContent().environmentObject(monitor).frame(width:620,height:600).preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light) }
    }
}

struct TaskCommands: Commands {
    func resizeWindow(width:CGFloat,height:CGFloat) {
        guard let window=NSApp.windows.first(where:{$0.identifier?.rawValue == "main"}) else {return}
        window.setContentSize(NSSize(width:width,height:height));window.makeKeyAndOrderFront(nil)
    }
    @ObservedObject var monitor:Monitor
    var body: some Commands {
            CommandGroup(after:.windowArrangement) {
                Button("Show System Gadget") {DispatchQueue.main.async {monitor.statusGadgets?.show()}}.keyboardShortcut("g",modifiers:[.command,.shift])
                Menu("Window Size") {
                    Button("Compact") {resizeWindow(width:780,height:600)}
                    Button("Standard") {resizeWindow(width:1100,height:760)}
                    Button("Wide") {resizeWindow(width:1400,height:850)}
                }
            }
            CommandGroup(replacing:.appInfo) {Button("About Houston") {showAbout()};Button("Check for Updates…") {HoustonUpdater.shared.check()}}
            CommandGroup(after:.textEditing) { Button("Find…") {NotificationCenter.default.post(name:Notification.Name("TaskManagerFind"),object:nil)}.keyboardShortcut("f",modifiers:.command) }
            CommandGroup(after:.newItem) { Button("Run New Task…") { monitor.runTask() }.keyboardShortcut(KeyEquivalent("n"),modifiers:.command); Button("Export Process List…") { monitor.export() }.keyboardShortcut("e",modifiers:[.command,.shift]) }
            CommandMenu("Navigate") { ForEach(Page.allCases.filter {$0 != .settings}) { p in Button(p.rawValue) { monitor.page = p } }; Divider(); Toggle("Always on Top",isOn:$monitor.alwaysOnTop); Button(monitor.paused ? "Resume Updates" : "Pause Updates") { monitor.paused.toggle() }.keyboardShortcut("p",modifiers:[.command,.shift]); Button("Refresh Now") { monitor.refresh(); monitor.refreshServices() }.keyboardShortcut(KeyEquivalent("r"),modifiers:.command) }
            CommandMenu("Process") { Button("Inspect") { monitor.inspector = monitor.chosen }.keyboardShortcut(KeyEquivalent("i"),modifiers:.command).disabled(monitor.chosen == nil); Button("End Task") { if let p = monitor.chosen { monitor.processAction("End task",proc:p) } }.keyboardShortcut(.delete,modifiers:.command).disabled(!monitor.canControl(monitor.chosen)) }
    }
}
