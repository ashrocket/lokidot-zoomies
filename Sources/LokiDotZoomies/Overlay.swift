import AppKit
import QuartzCore
import ZoomiesCore

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class Overlay {
    let window: PetPanel
    let stage = CALayer()
    let pet = CALayer()
    let route: MotionRoute
    private let restingImage = PetArtwork.image()
    private let frames = (0..<16).map { PetArtwork.image(phase: Double($0) / 16 * 2 * .pi, running: true) }

    init(screen: NSScreen) {
        let frame = screen.visibleFrame
        route = MotionRoute(bounds: CGRect(origin: .zero, size: frame.size))
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
        stage.addSublayer(pet)
        pet.bounds = CGRect(origin: .zero, size: route.spriteSize)
        pet.contentsGravity = .resizeAspect
        pet.contentsScale = screen.backingScaleFactor
        pet.contents = restingImage
        pet.position = route.sample(progress: 0).point
        pet.transform = Self.transform(route.sample(progress: 0))
        window.contentView = view
    }

    static func transform(_ sample: MotionSample) -> CATransform3D {
        let pose = MotionRoute.orientation(sample.tangent)
        let rotation = CATransform3DMakeRotation(pose.bank, 0, 0, 1)
        return CATransform3DScale(rotation, pose.facing, 1, 1)
    }

    func run(delegate: CAAnimationDelegate) {
        resetClock()
        pet.removeAllAnimations()
        let count = 960
        let samples = (0...count).map { route.sample(progress: Double($0) / Double(count)) }
        let positions = CAKeyframeAnimation(keyPath: "position")
        positions.values = samples.map { NSValue(point: $0.point) }
        positions.duration = MotionRoute.lapDuration
        positions.calculationMode = .linear
        let turns = CAKeyframeAnimation(keyPath: "transform")
        turns.values = samples.map { NSValue(caTransform3D: Self.transform($0)) }
        turns.duration = MotionRoute.lapDuration
        let stride = CAKeyframeAnimation(keyPath: "contents")
        stride.values = frames
        stride.calculationMode = .discrete
        stride.duration = 0.48
        stride.repeatCount = .infinity
        let lap = CAAnimationGroup()
        lap.animations = [positions, turns, stride]
        lap.duration = MotionRoute.lapDuration
        lap.delegate = delegate
        pet.add(lap, forKey: "zoomies")
    }

    func settle(keepPosition: Bool = false) {
        let position = keepPosition ? (pet.presentation()?.position ?? pet.position) : route.sample(progress: 0).point
        let transform = keepPosition ? (pet.presentation()?.transform ?? pet.transform) : Self.transform(route.sample(progress: 0))
        pet.removeAllAnimations()
        resetClock()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pet.position = position
        pet.transform = transform
        pet.contents = restingImage
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
