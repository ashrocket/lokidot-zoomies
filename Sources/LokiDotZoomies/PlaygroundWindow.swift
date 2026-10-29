import AppKit
import ZoomiesCore

@MainActor
final class PlaygroundWindow: NSWindowController {
    var onPlay: ((String, MotionStyle) -> Void)?
    var onPause: (() -> Void)?
    var onImport: (() -> Void)?
    private let pets = NSPopUpButton(frame: .zero, pullsDown: false)
    private let motions = NSPopUpButton(frame: .zero, pullsDown: false)
    private let status = NSTextField(wrappingLabelWithString: "Ready for a little chaos?")
    private let pause = NSButton(title: "Pause", target: nil, action: nil)
    private let play = NSButton(title: "Let’s go!", target: nil, action: nil)
    private let note = NSTextField(wrappingLabelWithString: "")
    private let copyPrompt = NSButton(title: "Copy setup prompt", target: nil, action: nil)
    private var jumpingAvailable: [String: Bool] = [:]
    private var committedPet: String?
    private var committedMotion: MotionStyle?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 610),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "LokiDot Zoomies"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Good dogs. Big zoomies.")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        let intro = NSTextField(wrappingLabelWithString: "A small pack of desktop companions, ready to play.")
        intro.textColor = .secondaryLabelColor
        root.addArrangedSubview(title); root.addArrangedSubview(intro)
        root.addArrangedSubview(field("Who’s playing?", control: pets))
        pets.target = self; pets.action = #selector(selectionChanged)
        for style in MotionStyle.allCases {
            motions.addItem(withTitle: style.title)
            motions.lastItem?.representedObject = style.rawValue
        }
        root.addArrangedSubview(field("Pick a move", control: motions))
        play.bezelStyle = .rounded; play.keyEquivalent = "\r"
        play.target = self; play.action = #selector(start)
        pause.bezelStyle = .rounded; pause.target = self; pause.action = #selector(togglePause)
        let buttons = NSStackView(views: [play, pause]); buttons.spacing = 10
        root.addArrangedSubview(buttons)
        status.font = .systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(status)
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)
        let ownDog = NSTextField(labelWithString: "Your dog deserves a turn.")
        ownDog.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(ownDog)
        let steps = NSTextField(wrappingLabelWithString: "1. Copy the setup prompt below.\n2. Paste it into your agent with a full-body dog photo.\n3. Let the agent create and check the animation pack.")
        steps.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(steps)
        let bring = NSButton(title: "Add your dog…", target: self, action: #selector(importDog))
        bring.bezelStyle = .rounded
        copyPrompt.bezelStyle = .rounded; copyPrompt.target = self; copyPrompt.action = #selector(copySetupPrompt)
        let dogButtons = NSStackView(views: [copyPrompt, bring]); dogButtons.spacing = 10
        root.addArrangedSubview(dogButtons)
        let hint = NSTextField(wrappingLabelWithString: "When your agent says the pack is ready, choose its finished folder with Add your dog. A photo alone won’t animate. The paw menu stays handy when you close this window.")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        root.addArrangedSubview(hint)
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -24),
            pets.widthAnchor.constraint(equalToConstant: 260), motions.widthAnchor.constraint(equalToConstant: 260)
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func field(_ title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        let stack = NSStackView(views: [label, control]); stack.orientation = .vertical
        stack.alignment = .leading; stack.spacing = 5
        control.setAccessibilityLabel(title)
        return stack
    }

    func update(characters: [(id: String, name: String, canPrance: Bool)], selected: String, motion: MotionStyle,
                status: String, paused: Bool, canPlay: Bool) {
        // A rest/pause update must not discard a choice the user is making.
        let pendingPet = pets.selectedItem?.representedObject as? String
        let pendingMotion = motions.selectedItem?.representedObject as? String
        let petID = committedPet == selected ? pendingPet ?? selected : selected
        let motionID = committedMotion == motion ? pendingMotion ?? motion.rawValue : motion.rawValue
        committedPet = selected; committedMotion = motion
        jumpingAvailable = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0.canPrance) })
        pets.removeAllItems()
        for character in characters {
            pets.addItem(withTitle: character.name); pets.lastItem?.representedObject = character.id
        }
        if let item = pets.itemArray.first(where: { $0.representedObject as? String == petID }) { pets.select(item) }
        if let item = motions.itemArray.first(where: { $0.representedObject as? String == motionID }) { motions.select(item) }
        motions.autoenablesItems = false
        self.status.stringValue = status
        selectionChanged()
        pause.title = paused ? "Resume" : "Pause"
        pause.isEnabled = canPlay; play.isEnabled = canPlay
    }

    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    @objc private func selectionChanged() {
        let id = pets.selectedItem?.representedObject as? String ?? ""
        let canPrance = jumpingAvailable[id] ?? false
        motions.itemArray.first(where: { $0.representedObject as? String == "prance" })?.isEnabled = canPrance
        if !canPrance && motions.selectedItem?.representedObject as? String == "prance" { motions.selectItem(at: 0) }
        note.stringValue = canPrance ? "Circles stay upright. Prancing uses the dog’s own jumping poses." : "This pack can run and circle. Add jumping poses in a pet-v2 pack to unlock prancing."
    }

    @objc private func start() {
        guard let id = pets.selectedItem?.representedObject as? String,
              let raw = motions.selectedItem?.representedObject as? String,
              let style = MotionStyle(rawValue: raw) else { return }
        onPlay?(id, style)
    }
    @objc private func togglePause() { onPause?() }
    @objc private func importDog() { onImport?() }
    @objc private func copySetupPrompt() {
        guard let url = Bundle.main.url(forResource: "DogSetupPrompt", withExtension: "txt"),
              let prompt = try? String(contentsOf: url, encoding: .utf8) else {
            copyPrompt.title = "Prompt unavailable"; return
        }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(prompt, forType: .string) { copyPrompt.title = "Prompt copied ✓" }
    }
}
