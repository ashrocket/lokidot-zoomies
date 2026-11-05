import AppKit
import ZoomiesCore

@MainActor
final class SavedPetsWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
    struct Row { let pet: SavedPet; let loaded: Bool }
    var onImport: (() -> Void)?
    var onLoad: ((String) -> Void)?
    var onUnload: ((String) -> Void)?
    var onRemove: ((String) -> Void)?
    private var rows: [Row] = []
    private let table = NSTableView()
    private let load = NSButton(title: "Load pet", target: nil, action: nil)
    private let unload = NSButton(title: "Unload pet", target: nil, action: nil)
    private let remove = NSButton(title: "Remove saved copy…", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 430),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Saved pets"; window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "A home for your whole pack.")
        title.font = .systemFont(ofSize: 23, weight: .bold)
        let intro = NSTextField(wrappingLabelWithString: "Imported pets are saved here and remembered when Zoomies starts. Loaded pets join The whole pack. Unload one to keep it saved for later.")
        intro.font = .systemFont(ofSize: 12); intro.preferredMaxLayoutWidth = 492
        root.addArrangedSubview(title); root.addArrangedSubview(intro)
        let name = NSTableColumn(identifier: .init("pet")); name.title = "Pet"; name.width = 310
        let state = NSTableColumn(identifier: .init("state")); state.title = "Status"; state.width = 140
        table.addTableColumn(name); table.addTableColumn(state)
        table.dataSource = self; table.delegate = self; table.rowHeight = 30
        table.allowsMultipleSelection = false; table.usesAlternatingRowBackgroundColors = true
        table.setAccessibilityLabel("Saved pets")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.documentView = table; root.addArrangedSubview(scroll)
        for button in [load, unload, remove] { button.target = self; button.bezelStyle = .rounded }
        load.action = #selector(loadPet); unload.action = #selector(unloadPet); remove.action = #selector(removePet)
        root.addArrangedSubview(NSStackView(views: [load, unload, remove]))
        let add = NSButton(title: "Import pet…", target: self, action: #selector(importPet)); add.bezelStyle = .rounded
        root.addArrangedSubview(add)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        root.addArrangedSubview(status)
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
            root.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -22),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor), scroll.heightAnchor.constraint(equalToConstant: 180),
            status.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func update(_ rows: [Row]) {
        let selected = selectedRow?.pet.id
        self.rows = rows; table.reloadData()
        if let index = rows.firstIndex(where: { $0.pet.id == selected }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else if !rows.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        selectionChanged()
    }
    private var selectedRow: Row? { rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil }
    private func selectionChanged() {
        let row = selectedRow
        load.isEnabled = row?.pet.problem == nil && row != nil
        unload.isEnabled = row?.loaded == true
        remove.isEnabled = row != nil
        status.stringValue = row?.pet.problem ?? (rows.isEmpty ? "No saved pets yet. Import a finished sprite-pack folder to start." : "Remove saved copy moves only LokiDot’s copy to Trash. Your original folder stays untouched.")
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = rows[row]
        let text = tableColumn?.identifier.rawValue == "pet" ? entry.pet.name : (entry.pet.problem != nil ? "Needs repair" : entry.loaded ? "Loaded" : "Unloaded")
        let field = NSTextField(labelWithString: text); field.lineBreakMode = .byTruncatingTail
        field.toolTip = tableColumn?.identifier.rawValue == "pet" ? entry.pet.id : text
        return field
    }
    func tableViewSelectionDidChange(_ notification: Notification) { selectionChanged() }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func importPet() { onImport?() }
    @objc private func loadPet() { if let row = selectedRow { onLoad?(row.pet.id) } }
    @objc private func unloadPet() { if let row = selectedRow { onUnload?(row.pet.id) } }
    @objc private func removePet() { if let row = selectedRow { onRemove?(row.pet.id) } }
}
