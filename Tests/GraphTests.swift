import Foundation
@main struct GraphTests {
    static func main() {
        let end=Date(timeIntervalSince1970:1000)
        for interval in [1.0,2.0,4.0] {
            // Deliberately offset samples from the 60 second left boundary.
            let points=stride(from:-70.7,through:0,by:interval).map { PlotPoint(date:end.addingTimeInterval($0),value:50+$0/2) }
            let bounded=boundedPlot(points,end:end,seconds:60)
            precondition(bounded.first!.date == end.addingTimeInterval(-60))
            precondition(abs(bounded.first!.value-20)<0.001)
            precondition(bounded.last!.date == end)
            precondition(bounded.allSatisfy { $0.date>=end.addingTimeInterval(-60) && $0.date<=end })
        }
        for width in [120.0,300,1000] {
            let tooltip=min(180,width-8)
            for pointer in stride(from:0.0,through:width,by:1) {
                let x=graphTooltipX(pointer:pointer,width:width,tooltipWidth:tooltip)
                precondition(x>=4 && x+tooltip<=width-4)
            }
        }
        precondition(graphTooltipX(pointer:290,width:300,tooltipWidth:180)==98)
        precondition(graphTooltipX(pointer:50,width:300,tooltipWidth:180)==62)
        let new=[PlotPoint(date:end.addingTimeInterval(-5),value:10)]
        precondition(boundedPlot(new,end:end,seconds:60).first!.date==new[0].date)
        precondition(processorColumnCount(10)==5)
        precondition(processorColumnCount(20)==4)
        print("PASS: no boundary gap at 1/2/4-second refresh; edge interpolation; startup history; processor grids")
    }
}
