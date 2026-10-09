# Houston

A native SwiftUI/AppKit system monitor for Apple silicon, macOS 26 or later.
Version 1.4. It follows the modern Windows Task Manager workflow and adapts
Mission Center UI resources into native Mac views with Liquid Glass.

## Run

Open `Houston.dmg` and drag `Houston.app` to Applications. The DMG
also contains the matching source archive and license notices. This build is ad-hoc signed, not Developer ID notarized.

## What changed in 1.4

- Sparkle 2.10.0 updater with signed updates, Check for Updates menu command, and an Updates pane.
- DMG installer with corresponding source, full license notices, and AI disclosure.

## Previous interface improvements

- Monitor-only sidebar with aligned SF Symbols and consistent spacing. Settings lives in the Houston menu (Command-comma).
- Native About Houston panel with app icon, build/version information, privacy summary, open-source credits, and license links.
- Native Settings panes: General, Monitoring, Menu Bar, Data, and Updates.
- Optional CPU, memory, GPU, disk, and network menu-bar gadgets with native AppKit icons and values, live graphs and quick controls. Enable each in Settings → Menu Bar.
- Restrained disclosure and graph animations respect Reduce Motion. Text, numeric readings, and sidebar selection remain static.
- Existing preferences and usage history are preserved across the rename.

## Implemented

- Seven pages: Processes, Performance, App history, Startup apps, Users,
  Details, and Services, plus Settings.
- Native toolbar, search, tables, context menus, file panels, Settings,
  keyboard shortcuts, and optional menu-bar CPU monitor.
- Collapsible process type groups, sortable CPU/memory/disk/PID columns,
  inspection, executable locations, CSV export, run new task, terminate,
  force quit, suspend/resume, and a lower-priority scheduling action.
- Overall CPU and individual logical processor graphs; optional kernel time.
- Physical memory, compressed memory, swap, network send/receive, GPU
  utilization when IOKit exposes it, and individual physical disk read/write
  graphs with device identity and capacity.
- Expanded Performance details: user/system/idle CPU, physical cores, active/wired/cached/free memory, allocated swap, device transfer totals, interface transfer totals, and graph averages/peaks.
- Uniform native sidebar row sizing and padding, Command-F search, aggregate app sorting, consistent Settings appearance, and confirmation before deleting history.
- Graph history of 30/60/120/300 seconds, smooth curves, sliding animation,
  filled areas, mini graphs, graph summary view, and statistics at the right
  or below graphs. Native navigation transitions respect Reduce Motion.
- Per-process recorded CPU/disk history saved locally. Recording only occurs
  while the app runs; it is not retroactive history from before installation.
- Startup launch-agent/daemon inventory and a Login Items System Settings
  handoff. Current-session launchd jobs with start/restart/stop actions,
  status filters, and configuration locations.

## Platform differences

This is a Mac implementation of the workflow, not every Windows kernel
feature. Startup permissions are managed through native Login Items rather
than changing another app's SMAppService registration. Users shows process
owners rather than Windows session disconnection controls. Services exposes
current-session launchd jobs; protected system jobs remain subject to macOS
permissions. The efficiency action lowers process priority, without claiming
Windows EcoQoS. Per-process network/GPU, Windows handles/registry/NUMA,
process dumps, temperatures, and fan controls are not presented.

CPU process percentages use all logical cores by default, like Windows;
Settings can switch to per-core percentages. Process memory is resident
memory; totals can count shared pages more than once. System memory in use
includes active, inactive, speculative, wired, and compressed pages, minus purgeable and file-backed pages. Disk charts show physical transfer
rates, not a fabricated active-time percentage. Network counters use 64-bit Ethernet/Wi-Fi totals to avoid tunnel double counting.
GPU data is hardware dependent; missing counters are omitted.

Actions check process ownership and creation time to avoid PID-reuse errors,
and ask for confirmation before terminating or changing scheduling. No
privileged helper or administrator installation is required. The app makes
no network requests and sends no telemetry.

## Build

Xcode command-line tools with the macOS 26+ SDK are required:

```sh
./Scripts/build.sh
```

The script compiles Swift and a small C bridge against Apple frameworks,
builds the app, stages it outside the workspace, ad-hoc signs it, creates a
ZIP, and verifies both the staged and extracted app. No Electron, GTK,
webview, npm, or Rust runtime is used.

## Tests

From this source folder:

```sh
mkdir -p /tmp/taskmanager-tests
xcrun clang -O2 Tests/MetricsTests.c Native/Metrics.c -o /tmp/taskmanager-tests/metrics
/tmp/taskmanager-tests/metrics
xcrun swiftc -parse-as-library Sources/GraphGeometry.swift Tests/GraphTests.swift -o /tmp/taskmanager-tests/graphs
/tmp/taskmanager-tests/graphs
```

Metrics tests compare CPU time against getrusage, and validate PID, ownership,
resident memory, threads, total CPU/kernel counters, and individual core
ranges. Graph tests verify the left-edge regression at 1/2/4-second sampling,
interpolation, startup history, and logical-processor grid arrangements.

## UI reference and license

The complete Mission Center `resources` UI tree and reference screenshots
are in `ReferenceUI/MissionCenter`. Its original GTK Blueprint files are
reference material; the running UI is rebuilt with SwiftUI/AppKit.
The graph renderer reference is in `ReferenceUI/GraphWidget`.

Mission Center reference revision:
`f4109d6ac4d467b3416969d3d17dcdd8c32989c9`.
Stats monitoring reference revision:
`e27b499f42ad5117777a11a3c6b29b7f0f4ae758`.

The app source and Mission Center UI adaptations are GPL-3.0-or-later.
Stats-derived monitoring approaches retain the MIT notice. See `LICENSE`
and `THIRD-PARTY-NOTICES.md` for the respective copyrights and terms.

App rows expand into descendants and helpers located within their app bundle. Parent rows sum CPU, resident memory, threads, and disk throughput. Shared pages may be counted more than once. Shared XPC helpers without a surviving parent relationship or app-specific executable path remain separate rather than guessed.

Graph hover displays the nearest recorded sample, its timestamp, and values for both series. Sampling supports 0.5/1/2/4 seconds; graph scrolling renders up to 60 fps. Network totals use 64-bit route counters for Ethernet/Wi-Fi interfaces, excluding VPN/tunnel duplicate traffic. Memory uses the Stats formula including inactive/speculative pages and subtracting purgeable/file-backed pages.

Running Safari app and web extensions are grouped beneath Safari by their NSExtensionPointIdentifier. Inactive extensions have no process row. The arrow includes Safari-named WebKit XPC services outside the Safari bundle.

The macOS UI revision uses NavigationSplitView, a standard sidebar List with system selection, native sidebar search, page titles in the window toolbar, and native inset alternating table rows. New installations follow the system appearance. Existing explicit theme choices remain respected.

Efficiency: miniature graphs redraw on samples; large scrolling graphs are capped at 30 fps. Process ownership is cached until topology changes, account names are cached, and menu-bar updates are coalesced. Sampling uses a utility task and prevents overlapping collections.

Process tables adapt to window width: compact views prioritize Name, CPU, Memory, and Disk; wider views restore PID, Status, and User. Columns use adjustable bounds, system typography, native inset selection and alternating rows. Window → Window Size provides Compact, Standard, and Wide presets.

Background monitoring is enabled by default. Settings → General → Keep monitoring when the window is closed controls this behavior. Closing the window keeps sampling and gadgets live; Quit Houston stops the app. Reopen from the Dock or a gadget’s Open Houston button. This does not enable launch at login.

Menu-bar gadgets share one compact native status-item strip, with only two points between gadgets. The strip is one clickable button opening a shared panel with every selected statistic and its graph. Fixed drawing bounds and native-font-sized value slots keep readings stable without clipping.

Transfer rates in the compact strip use B/K/M/G suffixes (bytes per second); tooltips and popovers show full units. This keeps rate slots close to the percentage slots in width.

The menu-bar summary is one gadget and one shared popover. Settings → Menu Bar selects included statistics. Window → Show System Gadget (Command-Shift-G) opens the same panel.

The unified panel uses compact summary rows with readings and details beside small graphs. Miniature graphs omit hover overlays; full Performance graphs retain detailed hover readouts. Popover height follows its content, and menu-bar SF Symbols preserve their natural proportions.

Drag the gadget header away from the menu bar to detach it as a floating window. It remains open until closed and keeps sampling. Clicking the menu-bar gadget brings an already detached window forward.


## AI usage and upstream credits

Houston was developed with substantial assistance from OpenAI Codex. See [AI_DISCLOSURE.md](AI_DISCLOSURE.md) for the full disclosure, also available in About Houston.

Houston adapts UI/graph work from [Mission Center](https://gitlab.com/mission-center-devs/mission-center) and [graph-widget](https://gitlab.com/mission-center-devs/graph-widget) under GPL-3.0-or-later, and monitoring approaches from [Stats](https://github.com/exelban/stats) under MIT. [Sparkle](https://github.com/sparkle-project/Sparkle) provides the updater. Full upstream attribution and license terms are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md), [LICENSE](LICENSE), and [SPARKLE-LICENSE.txt](SPARKLE-LICENSE.txt). These are bundled with the app. Houston is an independent adaptation; no upstream endorsement is implied.

## Distribution and corresponding source

Houston is distributed under GPL-3.0-or-later, without warranty. Every binary release includes `Houston-Source.zip` containing the corresponding editable source, build scripts, upstream references and notices. Supply that archive and license notices alongside the DMG when redistributing; Preserve upstream notices and identify your modifications. The official, unmodified Sparkle SDK is pinned by version and SHA-256 in `Scripts/setup-sparkle.sh`.

## Updates

Sparkle performs signed update checks, downloads, installation and relaunch. Settings → Updates offers manual checks, daily/weekly automatic checks, and optional automatic download/installation. Automatic checking is off initially. Updates are fetched from the public `anon-uk/Houston` repository. No account, token or private-repository settings are required. Update requests go to GitHub; system-profile submission is disabled.

The maintainer signing key stays in the build Mac's Keychain under Sparkle account `Houston`. Only the public key is in source. Back up the private key securely outside this repository; future releases must be signed with the same key. Use `Scripts/release.sh` after building, upload the DMG and source archive to the release, then generate `appcast.xml` with the public GitHub release download URL. Commit the feed after uploading the asset.

The publishing workflow accepts locally built and Sparkle-signed artifacts in `release-inputs/`, verifies the manifest SHA-256 checksums, then uploads the DMG, exact source archive and checksums as a GitHub release. No signing private key or personal access token is stored in Actions. Future releases must be built and signed locally before updating the manifest.
