// SettingsWindowController — #39: 設定ウィンドウ本体を owns する
// プロセス内シングルトン。
//
// CandidateWindowController の NSPanel と違い、こちらは普通の
// NSWindow — タイトルバー・クローズボタンを持つ通常の書類 window で
// よく、フォーカスを奪ってはいけない候補ウィンドウの制約はない。
//
// Nagi は LSUIElement（Dock アイコンなし）で、IMKit のメニュー項目
// (NagiInputController.menu()) から呼ばれるまで一度も前面に出ない
// —— FirstRunPrompt.swift と同じく、表示直前に
// NSApp.activate(ignoringOtherApps:) が要る。

import Cocoa
import SwiftUI

final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nagi の設定"
        // SettingsRootView 側の `.frame(minWidth:minHeight:...)` と対に
        // なる下限——ウィンドウだけを先に小さくドラッグされても
        // SwiftUI 側のレイアウトが壊れないようにする。
        window.minSize = NSSize(width: 480, height: 420)
        window.contentView = NSHostingView(rootView: SettingsRootView())
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    /// 何度呼んでも同じウィンドウを前面に出すだけ —— NagiInputController
    /// は IMKit の client 接続ごとに複数インスタンス化されうるが
    /// (docs/architecture.md)、設定ウィンドウはプロセスに一つで十分。
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
