import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 裏で待機するための起動（AppDelegate.slimDown を参照）では、Dock に出さない。
if AppDelegate.startsInBackground { app.setActivationPolicy(.accessory) }
app.run()
