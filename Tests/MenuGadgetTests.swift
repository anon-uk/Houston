import Foundation
import AppKit
@main struct MenuGadgetTests {
    @MainActor static func main() {
        assert(menuRate(0)=="0B")
        assert(menuRate(999.49)=="999B")
        assert(menuRate(999.5)=="1.0K")
        assert(menuRate(999_500)=="1.0M")
        assert(menuRate(.nan)=="—")
        for exponent in -3...30 {
            for multiplier in [0.0,1.0,9.94,9.95,99.0,999.49,999.5,1023.0] {
                let value=multiplier*pow(10,Double(exponent))
                let label=menuRate(value)
                assert(label.count <= 5,"Unbounded gadget label: \(label)")
                assert(!label.contains(","))
                let measured=(label as NSString).size(withAttributes:[.font:MenuGadgetGeometry.font]).width
                assert(measured <= MenuGadgetGeometry.rateWidth+0.01,"Menu label exceeds its drawing bounds: \(label)")
            }
        }
        print("PASS: bounded gadget labels, rate-unit boundaries, unavailable counters")
    }
}
