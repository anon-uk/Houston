import AppKit
let out = CommandLine.arguments[1]
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let px=size*scale
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:px,pixelsHigh:px,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        let n=CGFloat(px)
        let outer=NSBezierPath(roundedRect:NSRect(x:n*0.06,y:n*0.06,width:n*0.88,height:n*0.88),xRadius:n*0.2,yRadius:n*0.2)
        NSGradient(starting:NSColor(calibratedRed:0.14,green:0.56,blue:0.94,alpha:1),ending:NSColor(calibratedRed:0.04,green:0.16,blue:0.36,alpha:1))!.draw(in:outer,angle:90)
        NSColor.white.withAlphaComponent(0.18).setStroke();outer.lineWidth=n*0.012;outer.stroke()
        let screen=NSBezierPath(roundedRect:NSRect(x:n*0.19,y:n*0.24,width:n*0.62,height:n*0.53),xRadius:n*0.05,yRadius:n*0.05)
        NSColor.white.withAlphaComponent(0.13).setFill();screen.fill();NSColor.white.withAlphaComponent(0.8).setStroke();screen.lineWidth=n*0.025;screen.stroke()
        let line=NSBezierPath();line.move(to:NSPoint(x:n*0.26,y:n*0.43))
        for point in [(0.36,0.43),(0.42,0.61),(0.48,0.34),(0.55,0.53),(0.61,0.43),(0.74,0.43)] { line.line(to:NSPoint(x:n*point.0,y:n*point.1)) }
        NSColor.white.setStroke();line.lineWidth=n*0.027;line.lineJoinStyle = .round;line.lineCapStyle = .round;line.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let data=bitmap.representation(using:.png,properties:[:])!
        let filename="icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to:URL(fileURLWithPath:out).appendingPathComponent(filename))
    }
}
