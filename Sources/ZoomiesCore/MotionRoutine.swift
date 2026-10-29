import Foundation
import CoreGraphics

public enum MotionStyle: String, CaseIterable, Codable {
    case zoomies, circle, prance

    public var title: String {
        switch self {
        case .zoomies: return "Big zoomies"
        case .circle: return "Little circles"
        case .prance: return "Happy prance"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .zoomies: return MotionRoute.lapDuration
        case .circle: return 8
        case .prance: return 7
        }
    }
}

/// A pose, not an artwork recipe. Turning blends the two authored running
/// directions; gaze frames are never treated as a body turntable.
public struct MotionPose {
    public let point: CGPoint
    public let facing: Double
    public let bank: Double
    public let scaleX: Double
    public let scaleY: Double
    public let jumpProgress: Double?
    public let strideTime: TimeInterval

    public var rightWeight: Double { (facing + 1) / 2 }
}

/// Pure choreography shared by the desktop compositor and preview exporter.
/// Every routine returns to its starting position and has zero endpoint speed.
public struct MotionRoutine {
    public let style: MotionStyle
    public let route: MotionRoute
    public let index: Int
    public let count: Int

    public init(style: MotionStyle, bounds: CGRect, artworkSize: CGSize = MotionRoute.artworkSize,
                index: Int = 0, count: Int = 1) {
        self.style = style
        self.route = MotionRoute(bounds: bounds, artworkSize: artworkSize)
        self.count = max(1, count)
        self.index = min(max(0, index), max(1, count) - 1)
    }

    public func sample(progress: Double) -> MotionPose {
        let t = min(1, max(0, progress.isFinite ? progress : 0))
        let phase = Double(index) / Double(count)
        let safe = route.safeBounds
        let sizeScale = route.spriteSize.height / MotionRoute.artworkSize.height
        let time = t * style.duration
        switch style {
        case .zoomies:
            let sample = route.sample(progress: t, phase: phase)
            let turn = MotionRoute.orientation(sample.tangent)
            // Gait advances with distance: feet no longer sprint while the body
            // is accelerating out of, or coasting into, a rest.
            return MotionPose(point: sample.point, facing: turn.facing, bank: turn.bank * 0.55,
                              scaleX: 0.72 + 0.28 * abs(turn.facing), scaleY: 1,
                              jumpProgress: nil, strideTime: MotionRoute.distanceProgress(t) * style.duration)
        case .circle:
            let angle = .pi / 2 + 2 * .pi * phase + 4 * .pi * MotionRoute.distanceProgress(t)
            let rx = min(180 * sizeScale, safe.width * 0.30)
            let ry = min(64 * sizeScale, safe.height * 0.16)
            let point = CGPoint(x: safe.midX + rx * cos(angle), y: safe.midY + ry * sin(angle))
            let turn = MotionRoute.orientation(CGVector(dx: -rx * sin(angle), dy: ry * cos(angle)))
            let depth = 0.94 - 0.06 * sin(angle)
            return MotionPose(point: point, facing: turn.facing, bank: turn.bank * 0.35,
                              scaleX: depth * (0.72 + 0.28 * abs(turn.facing)), scaleY: depth,
                              jumpProgress: nil, strideTime: MotionRoute.distanceProgress(t) * style.duration)
        case .prance:
            // A short stagger gives the group a call-and-response rhythm. All
            // performers still land before the shared completion callback.
            let stagger = min(0.45, Double(count - 1) * 0.15)
            let delay = count > 1 ? stagger * Double(index) / Double(count - 1) : 0
            let local = min(1, max(0, (time - delay) / (style.duration - stagger)))
            let cycle = local * 6
            let hop = local == 1 ? 1 : cycle - floor(cycle)
            let lift = pow(sin(.pi * hop), 2)
            let travel = MotionRoute.distanceProgress(local)
            let sway = sin(2 * .pi * travel)
            let anchorX = safe.minX + safe.width * Double(index + 1) / Double(count + 1)
            let amplitude = min(38 * sizeScale, safe.width / Double(count + 1) * 0.18)
            let height = min(32 * sizeScale, safe.height * 0.10)
            let landing = pow(max(0, cos(2 * .pi * hop)), 8) * 0.035
            return MotionPose(point: CGPoint(x: anchorX + amplitude * sway,
                                             y: safe.minY + safe.height * 0.35 + height * lift),
                              facing: 0, bank: -0.045 * sway,
                              scaleX: 1 + landing, scaleY: 1 - landing,
                              jumpProgress: hop, strideTime: time)
        }
    }
}
