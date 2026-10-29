import AppKit
import QuartzCore
import ZoomiesCore

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class Overlay {
    private final class Performer {
        let artwork: SpriteArtwork
        let layer = CALayer()
        let left = CALayer()
        let right = CALayer()
        var routine: MotionRoutine
        init(artwork: SpriteArtwork, routine: MotionRoutine) { self.artwork = artwork; self.routine = routine }
    }
    let window: PetPanel
    let stage = CALayer()
    private var performers: [Performer] = []
    private let bounds: CGRect
    var pet: CALayer { performers[0].layer }
    var petCount: Int { performers.count }

    init(screen: NSScreen, artworks: [SpriteArtwork]) {
        precondition(!artworks.isEmpty)
        let frame = screen.visibleFrame
        bounds = CGRect(origin: .zero, size: frame.size)
        window = PetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "LokiDot Zoomies Overlay"
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.ignoresMouseEvents = true; window.level = .floating; window.hidesOnDeactivate = false
        window.isMovable = false; window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: bounds)
        view.wantsLayer = true; view.layer = stage; view.setAccessibilityElement(false)
        stage.frame = bounds
        for (index, artwork) in artworks.enumerated() {
            let routine = MotionRoutine(style: .zoomies, bounds: bounds, artworkSize: artwork.displaySize,
                                        index: index, count: artworks.count)
            let performer = Performer(artwork: artwork, routine: routine)
            performer.layer.bounds = CGRect(origin: .zero, size: routine.route.spriteSize)
            for sprite in [performer.left, performer.right] {
                sprite.frame = performer.layer.bounds
                sprite.contentsGravity = .resizeAspect
                sprite.contentsScale = screen.backingScaleFactor
                performer.layer.addSublayer(sprite)
            }
            performer.left.contents = artwork.idle[0]
            performer.right.opacity = 0
            performer.layer.position = routine.sample(progress: 0).point
            stage.addSublayer(performer.layer)
            performers.append(performer)
        }
        window.contentView = view
    }

    static func transform(_ pose: MotionPose) -> CATransform3D {
        let rotation = CATransform3DMakeRotation(pose.bank, 0, 0, 1)
        return CATransform3DScale(rotation, pose.scaleX, pose.scaleY, 1)
    }

    private func keyframes(_ key: String, _ values: [Any], duration: TimeInterval,
                           discrete: Bool = false) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: key)
        animation.values = values; animation.duration = duration
        animation.calculationMode = discrete ? .discrete : .linear
        return animation
    }

    func run(style: MotionStyle, delegate: CAAnimationDelegate) {
        resetClock()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, performer) in performers.enumerated() {
            for layer in [performer.layer, performer.left, performer.right] { layer.removeAllAnimations() }
            performer.routine = MotionRoutine(style: style, bounds: bounds, artworkSize: performer.artwork.displaySize,
                                              index: index, count: performers.count)
            let duration = style.duration
            let count = Int(duration * 60)
            // No per-frame AppKit work: poses, sprite contents, and turn blends
            // are compiled once; Core Animation owns their shared clock.
            let poses = (0...count).map { performer.routine.sample(progress: Double($0) / Double(count)) }
            let lap = CAAnimationGroup()
            lap.animations = [
                keyframes("position", poses.map { NSValue(point: $0.point) }, duration: duration),
                keyframes("transform", poses.map { NSValue(caTransform3D: Self.transform($0)) }, duration: duration),
                keyframes("zPosition", poses.map { -$0.point.y }, duration: duration)
            ]
            lap.duration = duration
            if index == 0 { lap.delegate = delegate }
            performer.layer.position = poses[0].point
            performer.layer.transform = Self.transform(poses[0])
            performer.layer.add(lap, forKey: "zoomies")
            if style == .prance {
                precondition(performer.artwork.canPrance)
                performer.left.opacity = 1; performer.right.opacity = 0
                performer.left.add(keyframes("contents", poses.map {
                    performer.artwork.jumpingFrame(progress: $0.jumpProgress!)
                }, duration: duration, discrete: true), forKey: "gait")
            } else {
                // Crossfade authored directions through turns without mirroring
                // artwork or squeezing the pet to an invisible, zero-width line.
                for (sprite, facingLeft) in [(performer.left, true), (performer.right, false)] {
                    sprite.add(keyframes("contents", poses.map {
                        performer.artwork.runningFrame(time: $0.strideTime, facingLeft: facingLeft)
                    }, duration: duration, discrete: true), forKey: "gait")
                    sprite.add(keyframes("opacity", poses.map {
                        facingLeft ? 1 - $0.rightWeight : $0.rightWeight
                    }, duration: duration), forKey: "turn")
                }
            }
        }
        CATransaction.commit()
    }

    func settle(keepPosition: Bool = false) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for performer in performers {
            let pose = performer.routine.sample(progress: 0)
            let position = keepPosition ? (performer.layer.presentation()?.position ?? performer.layer.position) : pose.point
            let transform = keepPosition ? (performer.layer.presentation()?.transform ?? performer.layer.transform) : Self.transform(pose)
            for layer in [performer.layer, performer.left, performer.right] { layer.removeAllAnimations() }
            performer.layer.position = position; performer.layer.transform = transform
            performer.left.contents = performer.artwork.idle[0]; performer.left.opacity = 1
            performer.right.opacity = 0
        }
        resetClock(); CATransaction.commit()
    }

    func pause() {
        let time = stage.convertTime(CACurrentMediaTime(), from: nil)
        stage.speed = 0; stage.timeOffset = time
    }
    func resume() {
        let time = stage.timeOffset
        stage.speed = 1; stage.timeOffset = 0; stage.beginTime = 0
        stage.beginTime = stage.convertTime(CACurrentMediaTime(), from: nil) - time
    }
    private func resetClock() { stage.speed = 1; stage.timeOffset = 0; stage.beginTime = 0 }
}
