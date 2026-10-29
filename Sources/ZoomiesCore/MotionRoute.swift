import Foundation
import CoreGraphics

public struct MotionSample {
    public let point: CGPoint
    public let tangent: CGVector
}

/// A closed, C1-continuous route. All movement math is independent of AppKit.
/// Distances are measured in display points, so wide/portrait displays keep an
/// even pace instead of speeding up on horizontal stretches.
public struct MotionRoute {
    public static let lapDuration: TimeInterval = 16
    public static let restDuration: TimeInterval = 24
    public static let artworkSize = CGSize(width: 144, height: 156)

    public let safeBounds: CGRect
    public let spriteSize: CGSize
    private let curves: [Cubic]
    private let table: [(distance: Double, parameter: Double)]
    public let length: Double

    private static let knots: [CGPoint] = [
        CGPoint(x: 0.76, y: 0.80), CGPoint(x: 0.20, y: 0.80),
        CGPoint(x: 0.09, y: 0.63), CGPoint(x: 0.30, y: 0.56),
        CGPoint(x: 0.79, y: 0.57), CGPoint(x: 0.92, y: 0.40),
        CGPoint(x: 0.84, y: 0.20), CGPoint(x: 0.63, y: 0.12),
        CGPoint(x: 0.46, y: 0.22), CGPoint(x: 0.57, y: 0.36),
        CGPoint(x: 0.71, y: 0.25), CGPoint(x: 0.57, y: 0.08),
        CGPoint(x: 0.29, y: 0.12), CGPoint(x: 0.12, y: 0.31),
        CGPoint(x: 0.24, y: 0.46), CGPoint(x: 0.49, y: 0.41),
        CGPoint(x: 0.73, y: 0.55), CGPoint(x: 0.89, y: 0.72)
    ]

    public init(bounds: CGRect, artworkSize: CGSize = Self.artworkSize) {
        let scale = min(1, max(0.05, min(bounds.width / 600, bounds.height / 450)))
        spriteSize = CGSize(width: artworkSize.width * scale,
                            height: artworkSize.height * scale)
        // Circumscribed radius protects every bank angle, including on tiny screens.
        let radius = hypot(spriteSize.width, spriteSize.height) / 2 + 12 * scale
        safeBounds = CGRect(x: bounds.minX + min(radius, bounds.width / 2),
                            y: bounds.minY + min(radius, bounds.height / 2),
                            width: max(0, bounds.width - radius * 2),
                            height: max(0, bounds.height - radius * 2))
        let region = safeBounds
        let points = Self.knots.map {
            CGPoint(x: region.minX + $0.x * region.width,
                    y: region.minY + $0.y * region.height)
        }
        curves = points.indices.map { i in
            let n = points.count
            let before = points[(i + n - 1) % n]
            let start = points[i]
            let end = points[(i + 1) % n]
            let after = points[(i + 2) % n]
            // Catmull–Rom converted to cubic Bézier, with broad, rounded turns.
            return Cubic(a: start, b: start + (end - before) * 0.20,
                         c: end - (after - start) * 0.20, d: end)
        }
        var accumulated = 0.0
        var samples = [(distance: 0.0, parameter: 0.0)]
        var previous = curves[0].point(0)
        for segment in curves.indices {
            for step in 1...120 {
                let t = Double(step) / 120
                let point = curves[segment].point(t)
                accumulated += hypot(point.x - previous.x, point.y - previous.y)
                samples.append((accumulated, Double(segment) + t))
                previous = point
            }
        }
        table = samples
        length = accumulated
    }

    /// Smooth acceleration/deceleration with a subtle mid-lap surge. Monotonic.
    public static func distanceProgress(_ progress: Double) -> Double {
        let t = min(1, max(0, progress.isFinite ? progress : 0))
        let eased = t - sin(2 * .pi * t) / (2 * .pi)
        return eased + 0.012 * sin(4 * .pi * eased)
    }

    public func sample(progress: Double, phase: Double = 0) -> MotionSample {
        let offset = phase.isFinite ? phase.truncatingRemainder(dividingBy: 1) : 0
        let fraction = (Self.distanceProgress(progress) + offset + 1).truncatingRemainder(dividingBy: 1)
        return sample(distanceFraction: fraction)
    }

    public func sample(distanceFraction: Double) -> MotionSample {
        let fraction = min(1, max(0, distanceFraction.isFinite ? distanceFraction : 0))
        let distance = fraction * length
        var low = 0
        var high = table.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if table[mid].distance < distance { low = mid } else { high = mid }
        }
        let span = table[high].distance - table[low].distance
        let mix = span > 0 ? (distance - table[low].distance) / span : 0
        let parameter = table[low].parameter + mix * (table[high].parameter - table[low].parameter)
        let segment = min(curves.count - 1, Int(parameter))
        let local = parameter - Double(segment)
        return MotionSample(point: curves[segment].point(local), tangent: curves[segment].tangent(local))
    }

    /// Continuously turns through a narrow side profile instead of snapping or
    /// flickering when the route changes horizontal direction.
    public static func orientation(_ tangent: CGVector) -> (facing: Double, bank: Double) {
        let magnitude = hypot(tangent.dx, tangent.dy)
        guard magnitude > 0.00001 else { return (-1, 0) }
        let facing = tanh(tangent.dx / magnitude * 5)
        let slope = atan2(tangent.dy, abs(tangent.dx))
        return (facing, min(0.60, max(-0.60, slope)) * facing)
    }
}

private struct Cubic {
    let a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint
    func point(_ t: Double) -> CGPoint {
        let s = 1 - t
        return a * (s*s*s) + b * (3*s*s*t) + c * (3*s*t*t) + d * (t*t*t)
    }
    func tangent(_ t: Double) -> CGVector {
        let s = 1 - t
        let p = (b-a) * (3*s*s) + (c-b) * (6*s*t) + (d-c) * (3*t*t)
        return CGVector(dx: p.x, dy: p.y)
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x+b.x, y: a.y+b.y) }
private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x-b.x, y: a.y-b.y) }
private func * (a: CGPoint, b: Double) -> CGPoint { CGPoint(x: a.x*b, y: a.y*b) }
