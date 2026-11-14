import AppKit
import Carbon.HIToolbox

/// グローバルショートカットのキーの組み合わせ（Carbon のキーコードと修飾キー）。
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String

    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘S")

    private static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// キー入力からショートカットを作る。⌘ / ⌃ / ⌥ のどれも含まない入力は対象外。
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard event.type == .keyDown, !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        var carbon = 0, symbols = ""
        for (flag, mask, symbol) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
                                     (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] where flags.contains(flag) {
            carbon |= mask
            symbols += symbol
        }
        let key = Self.named[Int(event.keyCode)]
            ?? (event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(carbon), label: symbols + key)
    }

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }
}

/// アプリが前面にいなくても反応するショートカット。Carbon のホットキーは
/// アクセシビリティ権限なしで使える。
final class HotKey {
    static var action: (() -> Void)?
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?

    /// 登録に成功していて、いま実際に反応する状態か。
    var isRegistered: Bool { ref != nil }

    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        if !Self.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            Self.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x4952_4E48), id: 1)
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}

/// 「キーを変更…」ダイアログの中で、押された組み合わせを受け取って表示する欄。
final class ShortcutRecorderView: NSView {
    private(set) var shortcut: Shortcut?
    private let label: NSTextField

    init(current: String) {
        label = NSTextField(labelWithString: current)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 44))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.font = .systemFont(ofSize: 22, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 8, width: 260, height: 28)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !capture(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool { capture(event) }

    private func capture(_ event: NSEvent) -> Bool {
        guard let pressed = Shortcut(event: event) else { return false }
        shortcut = pressed
        label.stringValue = pressed.label
        return true
    }
}
