import AppKit

/// Original vector artwork, drawn locally. No downloaded avatar or third-party asset.
enum PetArtwork {
    static func image(phase: Double = 0, running: Bool = false, scale: CGFloat = 2) -> CGImage {
        let context = CGContext(data: nil, width: Int(160 * scale), height: Int(120 * scale),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let compression = running ? max(0, cos(phase)) : 0
        if running {
            // Small gathered/extended body poses, with the legs moving in pairs.
            context.translateBy(x: 80, y: 60 + sin(phase * 2) * 1.5)
            context.scaleBy(x: 1 + cos(phase) * 0.025, y: 0.97 - compression * 0.025)
            context.translateBy(x: -80, y: -60)
        }
        let ink = color(0x26394A)
        let cream = color(0xFFF2D8)
        let ginger = color(0xD99A66)
        let teal = color(0x60D5C2)

        func path(_ draw: (CGMutablePath) -> Void, fill: CGColor? = nil,
                  stroke: CGColor? = ink, width: CGFloat = 3) {
            let p = CGMutablePath()
            draw(p)
            context.addPath(p)
            if let fill { context.setFillColor(fill) }
            if let stroke { context.setStrokeColor(stroke); context.setLineWidth(width) }
            context.drawPath(using: fill != nil ? (stroke != nil ? .fillStroke : .fill) : .stroke)
        }
        func leg(hip: CGPoint, offset: Double, far: Bool) {
            let stride = running ? sin(phase + offset) : 0
            let tuck = running ? max(0, cos(phase + offset)) : 0
            let knee = CGPoint(x: hip.x + stride * 15, y: 40 + tuck * 12)
            let foot = CGPoint(x: hip.x + stride * 31 + 8, y: 17 + tuck * 21)
            path({ p in
                p.move(to: hip); p.addQuadCurve(to: knee, control: CGPoint(x: hip.x + stride * 8, y: 45))
                p.addLine(to: foot); p.addLine(to: CGPoint(x: foot.x + 8, y: foot.y))
            }, stroke: ink, width: far ? 7 : 8)
            path({ p in
                p.move(to: hip); p.addQuadCurve(to: knee, control: CGPoint(x: hip.x + stride * 8, y: 45))
                p.addLine(to: foot); p.addLine(to: CGPoint(x: foot.x + 8, y: foot.y))
            }, stroke: far ? ginger : cream, width: far ? 3.5 : 4.5)
        }

        leg(hip: CGPoint(x: 55, y: 62), offset: 0.20, far: true)
        leg(hip: CGPoint(x: 97, y: 64), offset: .pi + 0.50, far: true)
        // A whippet's long, happy question-mark tail.
        path({ p in
            p.move(to: CGPoint(x: 49, y: 72))
            p.addCurve(to: CGPoint(x: 13, y: 94), control1: CGPoint(x: 26, y: 71), control2: CGPoint(x: 6, y: 75))
            p.addQuadCurve(to: CGPoint(x: 24, y: 101), control: CGPoint(x: 15, y: 106))
        }, stroke: ink, width: 7)
        path({ p in
            p.move(to: CGPoint(x: 49, y: 72))
            p.addCurve(to: CGPoint(x: 13, y: 94), control1: CGPoint(x: 26, y: 71), control2: CGPoint(x: 6, y: 75))
            p.addQuadCurve(to: CGPoint(x: 24, y: 101), control: CGPoint(x: 15, y: 106))
        }, stroke: ginger, width: 3.5)

        path({ p in
            p.move(to: CGPoint(x: 38, y: 68))
            p.addCurve(to: CGPoint(x: 89, y: 79), control1: CGPoint(x: 40, y: 91 + compression * 4), control2: CGPoint(x: 68, y: 86 + compression * 4))
            p.addCurve(to: CGPoint(x: 112, y: 97), control1: CGPoint(x: 103, y: 79), control2: CGPoint(x: 104, y: 90))
            p.addCurve(to: CGPoint(x: 135, y: 96), control1: CGPoint(x: 119, y: 106), control2: CGPoint(x: 131, y: 104))
            p.addLine(to: CGPoint(x: 141, y: 87)); p.addLine(to: CGPoint(x: 153, y: 83))
            p.addQuadCurve(to: CGPoint(x: 144, y: 74), control: CGPoint(x: 158, y: 74))
            p.addLine(to: CGPoint(x: 126, y: 76))
            p.addCurve(to: CGPoint(x: 109, y: 56), control1: CGPoint(x: 122, y: 69), control2: CGPoint(x: 119, y: 58))
            p.addCurve(to: CGPoint(x: 76, y: 61), control1: CGPoint(x: 96, y: 49), control2: CGPoint(x: 90, y: 62))
            p.addCurve(to: CGPoint(x: 38, y: 68), control1: CGPoint(x: 59, y: 66), control2: CGPoint(x: 44, y: 47))
            p.closeSubpath()
        }, fill: cream)
        path({ p in
            p.move(to: CGPoint(x: 43, y: 76))
            p.addCurve(to: CGPoint(x: 74, y: 82), control1: CGPoint(x: 46, y: 85), control2: CGPoint(x: 61, y: 86))
            p.addCurve(to: CGPoint(x: 64, y: 66), control1: CGPoint(x: 82, y: 72), control2: CGPoint(x: 70, y: 63))
            p.addCurve(to: CGPoint(x: 43, y: 76), control1: CGPoint(x: 54, y: 62), control2: CGPoint(x: 44, y: 65))
        }, fill: ginger, stroke: nil)
        // Folded ear and long muzzle keep the silhouette recognizably whippet-like.
        path({ p in
            p.move(to: CGPoint(x: 117, y: 98)); p.addLine(to: CGPoint(x: 104, y: 112))
            p.addQuadCurve(to: CGPoint(x: 102, y: 85), control: CGPoint(x: 98, y: 99))
            p.addQuadCurve(to: CGPoint(x: 117, y: 98), control: CGPoint(x: 114, y: 86))
        }, fill: ginger)
        path({ p in
            p.move(to: CGPoint(x: 108, y: 89)); p.addLine(to: CGPoint(x: 121, y: 79))
        }, stroke: ink, width: 8)
        path({ p in
            p.move(to: CGPoint(x: 108, y: 89)); p.addLine(to: CGPoint(x: 121, y: 79))
        }, stroke: teal, width: 4.5)
        context.setFillColor(color(0xF5C453))
        context.fillEllipse(in: CGRect(x: 117, y: 70, width: 7, height: 7))
        leg(hip: CGPoint(x: 52, y: 64), offset: 0, far: false)
        leg(hip: CGPoint(x: 103, y: 62), offset: .pi + 0.3, far: false)
        context.setFillColor(ink)
        context.fillEllipse(in: CGRect(x: 129, y: 89, width: 5.5, height: 6))
        context.fillEllipse(in: CGRect(x: 148, y: 79, width: 7, height: 5))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 130, y: 92, width: 1.8, height: 1.8))
        path({ p in
            p.move(to: CGPoint(x: 137, y: 78)); p.addQuadCurve(to: CGPoint(x: 144, y: 77), control: CGPoint(x: 141, y: 75))
        }, width: 1.5)
        return context.makeImage()!
    }

    private static func color(_ value: UInt32) -> CGColor {
        CGColor(red: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
