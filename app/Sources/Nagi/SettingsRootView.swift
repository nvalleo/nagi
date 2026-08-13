// SettingsRootView — #39/#40: 設定ウィンドウ全体のタブ切り替え。
//
// 「一般」（SettingsView、数個のトグル・スライダー）と「ユーザー辞書」
// （UserDictionaryView、一覧+追加/削除の CRUD）は画面の性質が違うので、
// 1 つの Form に詰め込まず別タブに分けてある。

import AppKit
import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Nagi は LSUIElement（Dock アイコンなし）なので、開いている
            // 他のウィンドウに混ざると設定ウィンドウだけ見た目の手がかり
            // が何もない。`NSImage.applicationIconName` は Info.plist の
            // `CFBundleIconFile`（Nagi.icns）を自動的に読む特別な名前
            // ——バンドル内のパスをこちらで組み立てる必要はない。
            HStack(spacing: 8) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable()
                    .frame(width: 32, height: 32)
                Text("Nagi")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            TabView {
                SettingsView()
                    .tabItem { Label("一般", systemImage: "gearshape") }
                UserDictionaryView()
                    .tabItem { Label("ユーザー辞書", systemImage: "character.book.closed") }
            }
        }
        // 固定 frame ではなく min/ideal を渡すことで、
        // SettingsWindowController 側で有効にした `.resizable` を
        // SwiftUI 側が殺さないようにする——単なる `.frame(width:
        // height:)` のままだとウィンドウを resizable にしても中身が
        // 追従せず、実質リサイズできないのと同じになる。
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 480)
    }
}
