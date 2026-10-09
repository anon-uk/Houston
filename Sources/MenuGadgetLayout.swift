// SPDX-License-Identifier: GPL-3.0-or-later
// Modified for Houston, 2026-10-09; see THIRD-PARTY-NOTICES.md.
import Foundation

// Menu-bar labels have a bounded length, without grouping separators.
// Popovers and accessibility descriptions retain the full readings.
func menuRate(_ bytesPerSecond:Double) -> String {
    guard bytesPerSecond.isFinite else {return "—"}
    let units=["B","K","M","G","T","P","E"]
    var value=max(0,bytesPerSecond),unit=0
    while value >= 999.5 && unit < units.count-1 {value /= 1000;unit += 1}
    if value >= 999.5 {return ">999E"}
    let digits=unit > 0 && value < 9.95 ? 1 : 0
    return String(format:"%.*f",digits,value)+units[unit]
}

import AppKit
@MainActor enum MenuGadgetGeometry {
    static let font=NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular)
    static let rateWidth:CGFloat = (["B","K","M","G","T","P","E"].flatMap {["999"+$0,"9.9"+$0]}+[">999E"]).map {($0 as NSString).size(withAttributes:[.font:font]).width}.max()!
    static let percentWidth:CGFloat = ("100%" as NSString).size(withAttributes:[.font:font]).width
}
