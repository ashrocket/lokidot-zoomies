import AppKit
import QuartzCore
import ZoomiesCore

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class Overlay {
    private struct Performer {
        let artwork: SpriteArtwork
        let layer: CALayer
        let route: MotionRoute
        let phase: Double
        func sample(_ progress: Double) -> MotionSample { route.sample(progress: progress, phase: phase) }
    }
    let window: PetPanel
    let stage = CALayer()
    private var performers: [Performer] = []
    var pet: CALayer { performers[0].layer }
    var petCount: Int { performers.count }

    init(screen: NSScreen, artworks: [SpriteArtwork]) {
        precondition(!artworks.isEmpty)
        let frame = screen.visibleFrame
        window = PetPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        window.title = "LokiDot Zoomies Overlay"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer = stage
        view.setAccessibilityElement(false)
        stage.frame = view.bounds
        for (index, artwork) in artworks.enumerated() {
            let route = MotionRoute(bounds: CGRect(origin: .zero, size: frame.size), artworkSize: artwork.displaySize)
            let layer = CALayer()
            let performer = Performer(artwork: artwork, layer: layer, route: route,
                                      phase: Double(index) / Double(artworks.count))
            layer.bounds = CGRect(origin: .zero, size: route.spriteSize)
            layer.contentsGravity = .resizeAspect
            layer.contentsScale = screen.backingScaleFactor
            layer.contents = artwork.idle[0]
            layer.position = performer.sample(0).point
            layer.transform = Self.transform(performer.sample(0))
            stage.addSublayer(layer)
            performers.append(performer)
        }
        window.contentView = view
    }

    static func transform(_ sample: MotionSample) -> CATransform3D {
        let pose = MotionRoute.orientation(sample.tangent)
        let rotation = CATransform3DMakeRotation(pose.bank, 0, 0, 1)
        return CATransform3DScale(rotation, abs(pose.facing), 1, 1)
    }

    func run(delegate: CAAnimationDelegate) {
        resetClock()
        for (index, performer) in performers.enumerated() {
            let pet = performer.layer
            pet.removeAllAnimations()
            let count = 960
            let samples = (0...count).map { performer.sample(Double($0) / Double(count)) }
            let positions = CAKeyframeAnimation(keyPath: "position")
            positions.values = samples.map { NSValue(point: $0.point) }
            positions.duration = MotionRoute.lapDuration
            positions.calculationMode = .linear
            let turns = CAKeyframeAnimation(keyPath: "transform")
            turns.values = samples.map { NSValue(caTransform3D: Self.transform($0)) }
            turns.duration = MotionRoute.lapDuration
            let stride = CAKeyframeAnimation(keyPath: "contents")
            stride.values = samples.enumerated().map { frame, sample in
                performer.artwork.runningFrame(time: Double(frame) / Double(count) * MotionRoute.lapDuration,
                                               facingLeft: sample.tangent.dx < 0)
            }
            stride.calculationMode = .discrete
            stride.duration = MotionRoute.lapDuration
            let lap = CAAnimationGroup()
            lap.animations = [positions, turns, stride]
            lap.duration = MotionRoute.lapDuration
            // One completion controls the shared rest timer for the whole group.
            if index == 0 { lap.delegate = delegate }
            pet.add(lap, forKey: "zoomies")
        }
    }

    func settle(keepPosition: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for performer in performers {
            let pet = performer.layer
            let position = keepPosition ? (pet.presentation()?.position ?? pet.position) : performer.sample(0).point
            let transform = keepPosition ? (pet.presentation()?.transform ?? pet.transform) : Self.transform(performer.sample(0))
            pet.removeAllAnimations()
            pet.position = position
            pet.transform = transform
            pet.contents = performer.artwork.idle[0]
        }
        resetClock()
        CATransaction.commit()
    }

    func pause() {
        let pausedTime = stage.convertTime(CACurrentMediaTime(), from: nil)
        stage.speed = 0
        stage.timeOffset = pausedTime
    }

    func resume() {
        let pausedTime = stage.timeOffset
        stage.speed = 1
        stage.timeOffset = 0
        stage.beginTime = 0
        stage.beginTime = stage.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
    }

    private func resetClock() {
        stage.speed = 1
        stage.timeOffset = 0
        stage.beginTime = 0
    }
}
