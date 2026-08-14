// SettingsRootView — #39/#40: tab switcher for the whole settings
// window.
//
// "General" (SettingsView, a handful of toggles/sliders) and "User
// Dictionary" (UserDictionaryView, a list plus add/delete CRUD) are
// different enough in nature that they're split into separate tabs
// rather than crammed into one Form.

import AppKit
import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Nagi is LSUIElement (no Dock icon), so if this window ends
            // up mixed in among other open windows there's otherwise no
            // visual cue telling them apart. NSImage.applicationIconName
            // is a special name that automatically resolves to
            // Info.plist's CFBundleIconFile (Nagi.icns) — no need to
            // build the bundle path ourselves.
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
        // min/ideal instead of a fixed frame, so this doesn't override
        // the `.resizable` style mask SettingsWindowController sets on
        // the window — a plain `.frame(width:height:)` here would make
        // the window technically resizable but the SwiftUI content
        // wouldn't follow, which amounts to the same thing as not
        // resizable at all.
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 480)
    }
}
