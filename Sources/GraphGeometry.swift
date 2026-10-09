// SPDX-License-Identifier: GPL-3.0-or-later
// Modified for Houston, 2026-10-09; see THIRD-PARTY-NOTICES.md.
import Foundation
struct PlotPoint { var date: Date; var value: Double }
// Keep the sample before the visible boundary and interpolate at the edge.
// A mature time window therefore starts at x=0 instead of one sample-width in.
func boundedPlot(_ points: [PlotPoint], end: Date, seconds: Double) -> [PlotPoint] {
    let start = end.addingTimeInterval(-seconds)
    let candidates = points.filter { $0.date <= end }
    guard !candidates.isEmpty else { return [] }
    guard let index = candidates.firstIndex(where: { $0.date >= start }) else { return [] }
    var result = Array(candidates[index...])
    if index > 0, result[0].date > start {
        let before = candidates[index-1], after = result[0]
        let fraction = start.timeIntervalSince(before.date) / after.date.timeIntervalSince(before.date)
        result.insert(PlotPoint(date:start,value:before.value + (after.value-before.value)*fraction),at:0)
    }
    if let last = result.last, last.date < end { result.append(PlotPoint(date:end,value:last.value)) }
    return result
}
// Adapted from Mission Center cpu.rs compute_column_count (GPL-3.0-or-later).
// Copyright 2023 Romeo Calota; Copyright 2026 Mission Center Developers.
func processorColumnCount(_ count:Int) -> Int {
    if count <= 3 { return max(1,count) }
    let root = Int(Double(count).squareRoot().rounded())
    for value in root..<min(count,root*2) { if count % value == 0 { return value } }
    return root
}

// Flip the tooltip to the pointer's left at the right edge, keeping it in the plot.
func graphTooltipX(pointer:Double, width:Double, tooltipWidth:Double) -> Double {
    let proposed = pointer + 12 + tooltipWidth <= width - 4 ? pointer + 12 : pointer - tooltipWidth - 12
    return min(max(4,proposed),max(4,width-tooltipWidth-4))
}
