import AppKit
import Carbon.HIToolbox

/// クリックすると記録状態になり、次に押したキーの組み合わせを受け取るボタン。
final class ShortcutRecorder: NSButton {
    var shortcut: Shortcut { didSet { refresh() } }
    var onCapture: ((Shortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private(set) var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            refresh()
            onRecordingChange?(isRecording)
        }
    }

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        title = isRecording ? "キーを押す…" : shortcut.label
    }

    @objc private func toggleRecording() {
        if isRecording {
            isRecording = false
        } else {
            window?.makeFirstResponder(self)
            isRecording = true
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if !record(event) { super.keyDown(with: event) }
    }

    // ⌘ を含む組み合わせは keyDown ではなくこちらに届く。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        record(event) || super.performKeyEquivalent(with: event)
    }

    private func record(_ event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return false }
        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
        } else if let pressed = Shortcut(event: event) {
            onCapture?(pressed)
            isRecording = false
        } else {
            NSSound.beep()   // 修飾キーなしの入力は受け付けない
        }
        return true
    }
}

/// 3つの撮り方それぞれのショートカットを、変更・オンオフする設定ウインドウ。
final class SettingsWindowController: NSObject {
    private let center = ShortcutCenter.shared
    private let hint = "ボタンをクリックしてから、新しい組み合わせを押してください（⌘ / ⌃ / ⌥ のいずれかを含む）。esc で取り消せます。"
    private var rows: [(mode: CaptureMode, toggle: NSButton, recorder: ShortcutRecorder, note: NSTextField)] = []
    private lazy var message = NSTextField(wrappingLabelWithString: hint)
    private(set) lazy var window = makeWindow()

    func show() {
        let window = window   // 初回はここで組み立てる。refresh より先に行が必要。
        refresh()
        report(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.yPlacement = .center
        for mode in CaptureMode.allCases {
            let toggle = NSButton(checkboxWithTitle: mode.title, target: self, action: #selector(toggled))
            let recorder = ShortcutRecorder(shortcut: center.shortcut(for: mode))
            let note = NSTextField(labelWithString: "")
            note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            note.textColor = .systemRed
            recorder.onCapture = { [weak self] in self?.captured($0, for: mode) }
            recorder.onRecordingChange = { [weak self] in self?.recordingChanged($0) }
            grid.addRow(with: [toggle, recorder, note])
            rows.append((mode, toggle, recorder, note))
        }
        grid.column(at: 2).width = 110

        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.preferredMaxLayoutWidth = 440
        let reset = NSButton(title: "初期設定に戻す", target: self, action: #selector(resetAll))
        reset.controlSize = .small

        let stack = NSStackView(views: [grid, message, reset])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ショートカット設定"
        window.isReleasedWhenClosed = false
        window.contentView = stack
        window.setContentSize(stack.fittingSize)
        window.center()
        return window
    }

    /// 設定の現在値を画面に反映する。
    private func refresh() {
        // 記録中は全部を一時的に外しているので、その間は「使用中」と表示しない。
        let recording = rows.contains { $0.recorder.isRecording }
        for row in rows {
            let enabled = center.isEnabled(row.mode)
            row.toggle.state = enabled ? .on : .off
            row.recorder.shortcut = center.shortcut(for: row.mode)
            // オンなのに効いていないものは、黙って効かないままにしない。
            row.note.stringValue = enabled && !recording && !center.isActive(row.mode) ? "ほかで使用中" : ""
        }
    }

    private func report(_ problem: String?) {
        message.stringValue = problem ?? hint
        message.textColor = problem == nil ? .secondaryLabelColor : .systemRed
    }

    @objc private func toggled(_ sender: NSButton) {
        guard let row = rows.first(where: { $0.toggle === sender }) else { return }
        center.setEnabled(sender.state == .on, for: row.mode)
        report(nil)
        refresh()
    }

    @objc private func resetAll(_ sender: Any?) {
        window.makeFirstResponder(nil)
        center.resetAll()
        report(nil)
        refresh()
    }

    private func recordingChanged(_ recording: Bool) {
        if recording {
            center.suspend()
            report(nil)
        } else {
            center.resume()
        }
        refresh()
    }

    private func captured(_ shortcut: Shortcut, for mode: CaptureMode) {
        switch center.set(shortcut, for: mode) {
        case nil:
            report(nil)
        case .usedBy(let other):
            report("\(shortcut.label) は「\(other.title)」で使っています。別の組み合わせを選んでください。")
        case .unavailable:
            report("\(shortcut.label) は登録できませんでした。ほかのアプリが使っている可能性があります。")
        }
    }
}
