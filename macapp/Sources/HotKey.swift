import AppKit
import Carbon.HIToolbox

/// スクリーンショットの撮り方。それぞれに専用のショートカットを持つ。
enum CaptureMode: String, CaseIterable {
    case screen, area, window

    var title: String {
        switch self {
        case .screen: "画面全体を撮影"
        case .area: "範囲を選んで撮影"
        case .window: "ウインドウを選んで撮影"
        }
    }

    var defaultShortcut: Shortcut {
        let (code, key) = switch self {
        case .screen: (kVK_ANSI_7, "7")
        case .area: (kVK_ANSI_8, "8")
        case .window: (kVK_ANSI_9, "9")
        }
        return Shortcut(keyCode: UInt32(code), modifiers: UInt32(shiftKey | cmdKey), key: key)
    }

    fileprivate var hotKeyID: UInt32 { UInt32(Self.allCases.firstIndex(of: self)! + 1) }
}

/// グローバルショートカットのキーの組み合わせ（Carbon のキーコードと修飾キー）。
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// 表示用のキー名（"7"、"Space"、"F5" など）。
    var key: String

    private static let flags: [(flag: NSEvent.ModifierFlags, carbon: Int, symbol: String)] = [
        (.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘"),
    ]

    /// 文字にならないキーの表示名と、メニューに出すときの文字。
    private static let named: [Int: (name: String, menu: String)] = {
        var keys: [Int: (String, String)] = [
            kVK_Space: ("Space", " "), kVK_Return: ("↩", "\r"), kVK_Tab: ("⇥", "\t"),
            kVK_Delete: ("⌫", "\u{8}"), kVK_ForwardDelete: ("⌦", "\u{7F}"),
            kVK_UpArrow: ("↑", "\u{F700}"), kVK_DownArrow: ("↓", "\u{F701}"),
            kVK_LeftArrow: ("←", "\u{F702}"), kVK_RightArrow: ("→", "\u{F703}"),
        ]
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (i, code) in functionKeys.enumerated() {
            keys[code] = ("F\(i + 1)", String(UnicodeScalar(0xF704 + i)!))
        }
        return keys
    }()

    static func == (a: Shortcut, b: Shortcut) -> Bool {
        a.keyCode == b.keyCode && a.modifiers == b.modifiers
    }

    var label: String {
        Self.flags.filter { Int(modifiers) & $0.carbon != 0 }.map(\.symbol).joined() + key
    }

    /// メニュー項目の右側にショートカットを表示するための値。
    var menuKey: String { Self.named[Int(keyCode)]?.menu ?? key.lowercased() }
    var menuModifiers: NSEvent.ModifierFlags {
        Self.flags.reduce(into: []) { if Int(modifiers) & $1.carbon != 0 { $0.insert($1.flag) } }
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// キー入力からショートカットを作る。⌘ / ⌃ / ⌥ のどれも含まない入力は対象外。
    init?(event: NSEvent) {
        let pressed = event.modifierFlags
        guard event.type == .keyDown, !pressed.intersection([.command, .control, .option]).isEmpty else { return nil }
        let carbon = Self.flags.reduce(0) { pressed.contains($1.flag) ? $0 | $1.carbon : $0 }
        let key = Self.named[Int(event.keyCode)]?.name
            ?? (event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? "").uppercased()
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(carbon), key: key)
    }

    fileprivate init?(stored: [String: Any]?) {
        guard let code = stored?["keyCode"] as? Int, let modifiers = stored?["modifiers"] as? Int,
              let key = stored?["key"] as? String else { return nil }
        self.init(keyCode: UInt32(code), modifiers: UInt32(modifiers), key: key)
    }

    fileprivate var stored: [String: Any] {
        ["keyCode": Int(keyCode), "modifiers": Int(modifiers), "key": key]
    }
}

/// 撮り方ごとのショートカットの設定を保存し、アプリが前面にいなくても反応するように登録する。
/// Carbon のホットキーはアクセシビリティ権限なしで使える。
final class ShortcutCenter {
    static let shared = ShortcutCenter()

    enum Rejection {
        case usedBy(CaptureMode)   // このアプリの別の撮り方で使っている
        case unavailable           // ほかのアプリやシステムに取られていて登録できない
    }

    var onPress: ((CaptureMode) -> Void)?
    private let defaults = UserDefaults.standard
    private var refs: [CaptureMode: EventHotKeyRef] = [:]
    private var suspended = false

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = id.id
            DispatchQueue.main.async {
                if let mode = CaptureMode.allCases.first(where: { $0.hotKeyID == pressed }) {
                    ShortcutCenter.shared.onPress?(mode)
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    // MARK: 設定の読み書き

    func shortcut(for mode: CaptureMode) -> Shortcut {
        Shortcut(stored: defaults.dictionary(forKey: "shortcut.\(mode.rawValue)")) ?? mode.defaultShortcut
    }

    func isEnabled(_ mode: CaptureMode) -> Bool {
        defaults.object(forKey: "shortcut.\(mode.rawValue).enabled") as? Bool ?? true
    }

    /// オンにしていて、実際に登録もできている（押せば反応する）か。
    func isActive(_ mode: CaptureMode) -> Bool { refs[mode] != nil }

    /// キーの組み合わせを変える。使えない組み合わせなら理由を返し、設定は変えない。
    func set(_ shortcut: Shortcut, for mode: CaptureMode) -> Rejection? {
        if let other = CaptureMode.allCases.first(where: { $0 != mode && self.shortcut(for: $0) == shortcut }) {
            return .usedBy(other)
        }
        unregister(mode)
        guard let probe = makeHotKey(shortcut, for: mode) else {
            register(mode)
            return .unavailable
        }
        UnregisterEventHotKey(probe)
        defaults.set(shortcut.stored, forKey: "shortcut.\(mode.rawValue)")
        register(mode)
        return nil
    }

    func setEnabled(_ enabled: Bool, for mode: CaptureMode) {
        defaults.set(enabled, forKey: "shortcut.\(mode.rawValue).enabled")
        register(mode)
    }

    func resetAll() {
        for mode in CaptureMode.allCases {
            defaults.removeObject(forKey: "shortcut.\(mode.rawValue)")
            defaults.removeObject(forKey: "shortcut.\(mode.rawValue).enabled")
        }
        registerAll()
    }

    // MARK: 登録

    func registerAll() {
        CaptureMode.allCases.forEach(register)
    }

    /// キーを記録している間は、いまのショートカットが発動しないよう一時的に外す。
    func suspend() {
        suspended = true
        CaptureMode.allCases.forEach(unregister)
    }

    func resume() {
        suspended = false
        registerAll()
    }

    private func register(_ mode: CaptureMode) {
        unregister(mode)
        if !suspended, isEnabled(mode) { refs[mode] = makeHotKey(shortcut(for: mode), for: mode) }
    }

    private func unregister(_ mode: CaptureMode) {
        if let ref = refs.removeValue(forKey: mode) { UnregisterEventHotKey(ref) }
    }

    private func makeHotKey(_ shortcut: Shortcut, for mode: CaptureMode) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4952_4E48), id: mode.hotKeyID)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }
}
