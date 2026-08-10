🇯🇵 日本語 ・ [🇺🇸 English](README.md)

# app — M1: 文字確定できる空の IME

IMKit のスケルトンをシステム設定に登録し、TextEdit にテキストを書き込めるようにする。まだ変換はしない（それは M2 で、`MozcClient`経由 — [`poc/`](../poc) 参照）— ここでは nagi が入力モードを保持できることだけを証明する。

## ここにあるもの

- `Package.swift` — 外部依存なしのプレーンな SwiftPM 実行可能ターゲット。`Cocoa` / `InputMethodKit`はシステムフレームワークで暗黙的にリンクされる。
- `Sources/Nagi/main.swift` — プロセスのエントリーポイント。`Info.plist`で宣言された接続名の下に`IMKServer`を立ち上げ、アクセサリ（Dock アイコンなし）アプリとして実行する。
- `Sources/Nagi/NagiInputController.swift` — `IMKInputController`のサブクラス。入力されたローマ字をバッファし、`setMarkedText`で下線付きの未確定文字として表示、Enter で`insertText`により変換後のひらがなを確定する。
- `Sources/Nagi/RomajiConverter.swift` — 小さな貪欲法によるローマ字→ひらがな変換テーブル。意図的に Mozc ではない — 理由はファイルヘッダー参照。
- `Resources/Info.plist` — IMKit 登録用のメタデータ（接続名、コントローラークラス、宣言された入力モード）。google/mozc 自身の`mac/Info.plist`、macSKK、Apple の純正バンドル`/System/Library/Input Methods/AinuIM.app`と照合し、間違えやすいキーを正しく設定した（下記「登録されるまで」参照 — 「キーを正しく設定する」以上の手間がかかった）。
- `Resources/InfoPlist.strings` — 入力ソースピッカー用の表示名。これがないと、macOS は"Nagi"/"ひらがな"の代わりに生の`TISInputSourceID`文字列を表示する。
- `Resources/icons/nagi.tiff` — プレースホルダーのモードアイコン（汎用システムアイコンで、本物のアートワークではない — 実リリース前に見直すこと）。

## `.xcodeproj`がない理由

[`poc/`](../poc) と同じ理由: この環境には Xcode の Command Line Tools はあるが、Xcode GUI はなく、プロジェクトは M0 以降 SwiftPM ベースになっている。IMKit の`.app`に Xcode は不要 — 正しい`Info.plist`キーを持つバンドル内に有効な Mach-O バイナリがあればよく、`scripts/build-app.sh`が素の`swift build`の出力から手作業で組み立てる。（M1 の途中で Xcode 自体は dev マシンにインストールされることになった。無料の Apple ID 開発証明書を得るためで、行き詰まった署名関連の仮説を追っていたときのこと — 下記参照 — だがビルド自体は今でも Xcode を使わない。）誰かが Xcode GUI 環境でこのプロジェクトを引き継ぎ、M3 向けによりリッチな Interface Builder／アセットカタログ機能を使いたくなったときに見直すこと。

## ビルド

```sh
./scripts/build-app.sh          # release（デフォルト）
./scripts/build-app.sh debug    # コンパイルはできるが、絶対に登録されない — 下記参照
```

`.build-app/Nagi.app`を生成する（デフォルトで ad-hoc 署名。`security find-identity`のハッシュを`CODESIGN_IDENTITY`に設定すれば実署名も可能 — 必須ではなく、ad-hoc で十分動作する）。

## ビルド済み配布（.dmg）

フルの開発環境（Xcode、Bazel、...— 上記「ビルド」参照）なしで Nagi を試したい場合: `scripts/build-dmg.sh`がビルド済みの`Nagi.app`を、ドラッグ＆ドロップだけで使えるプレーンな`.dmg`にパッケージングする — 中身はアプリのみ、インストーラーパッケージはなし。まだ GitHub Release には添付していない（リリースをまだ切っていないため）ので、今のところローカルでビルドする必要がある:

```sh
./scripts/build-dmg.sh   # -> .build-dmg/Nagi-<version>.dmg
```

意図的に「アプリのみ」であり、`.pkg`／カスタムインストーラーではない — 署名・公証済みで、アプリだけが入っていて、ユーザーが好きな場所にドラッグできる DMG というのが、大手企業のインストーラーの外側で見ると、個人／小規模チームの macOS 開発者が実際に収斂している標準だから（#30 で議論、[この r/opensource のスレッド](https://www.reddit.com/r/opensource/comments/1ku0zv0/) のご指摘に感謝 — このセクションの以前のバージョンは`.pkg`を指していた）。唯一必要な配慮: Nagi は`/Applications/`ではなく`/Library/Input Methods/`に置かれる必要があるため、DMG のドロップ先は通常の Applications エイリアスではなく、そのフォルダへのシンボリックリンクになっている。カスタムインストーラーを不要にできた理由: `Nagi.app`は初回起動時に`SMAppService`経由で自分自身の`NagiConverter` LaunchAgent を登録するようになった（`app/Sources/Nagi/ConverterServiceRegistration.swift`参照）ほか、M4 の #30 フォローアップとして、reboot 不要で自分自身を Text Input Source として登録するようにもなった（`app/Sources/Nagi/InputSourceRegistration.swift`、下記「登録されるまで」参照）— もはやインストーラースクリプトがそのどちらも代行する必要はない。

**未署名 — このリポジトリの背後に Apple Developer Program のメンバーシップ（Developer ID）は存在しないため、macOS の Gatekeeper が`Nagi.app`の初回起動をブロックする。** Nagi.app を Control-click → 開く → 開く（ダイアログでもう一度）、または初回のブロック後にシステム設定 → プライバシーとセキュリティ → 「このまま開く」。どちらも「開く」の選択肢が出ない場合（最近の macOS では代わりに「壊れている」と表示され、GUI での回避手段がないことがある — 上記スレッドでも指摘あり）、quarantine 属性を手動で剥がす: `xattr -cr "/Library/Input Methods/Nagi.app"`。このフォールバックを含む完全な手順は`scripts/dmg/README.txt`（DMG 内に同梱）にある。これは同じく個人開発の macOS IME である[SwiftyGyaim](https://github.com/tanabe1478/SwiftyGyaim) が同じ理由で行っているのと同じトレードオフ。署名・公証済み DMG（macSKK/AquaSKK/azooKey-Desktop に合わせる、いずれも#30 で調査済み）はまだ roadmap（M4）上にある — 有償の Developer ID が先に必要。

## インストール（ソースから）

```sh
./scripts/install-ime.sh                  # ~/Library/Input Methods/
./scripts/install-ime.sh release --system # /Library/Input Methods/（sudo）
```

**その後、手動で:**

1. **`Nagi.app`を一度起動する** — Finder でダブルクリックするか、`open "/Library/Input Methods/Nagi.app"`。これにより自己登録がトリガーされる（`app/Sources/Nagi/InputSourceRegistration.swift`、#30 フォローアップ）— **もう reboot は不要。** このドキュメントの以前のバージョンではここでフルの reboot が必要としていたが、なぜそれが必須ではなくなったかは下記「登録されるまで」を参照。
2. システム設定 → キーボード → 入力ソース に、「+」を押さなくても既に「Nagi」が日本語の下に並んでいるはず（自己登録が直接有効化する）。他の日本語 IME（Google 日本語入力、macSKK など）がインストールされている場合、「ひらがな」という名前のエントリが複数あることがある — モードアイコンで見分けること。もし出てこない場合は、編集... → 「+」→ 日本語の下の「Nagi」を探す → 追加、にフォールバックする。
3. メニューバーの入力メニューから切り替える。
4. TextEdit で`nagi`と入力して Enter。

## アンインストール

```sh
./scripts/uninstall-ime.sh                  # ~/Library/Input Methods/
./scripts/uninstall-ime.sh --system         # /Library/Input Methods/（sudo）
./scripts/uninstall-ime.sh --all            # 両方
```

上記の`.dmg`経由でインストールした場合は`/Library/Input Methods/`なので`--system`を使うこと。

`Nagi.app`を削除し、`NagiConverter` LaunchAgent を停止する。#30 のインストール/アンインストール対応まで存在しなかった — `install-ime.sh`にはそれまで対になるスクリプトがなかった。

**確認済み（#30）: reboot は不要だが、手動の一手間は必要。** このスクリプトを実行した後も「ひらがな (Nagi)」はシステム設定の入力ソース一覧に残り続ける — reboot しない限り自動では消えない — が、実体のバンドルが消えているため切り替えはできなくなる。即座に（reboot 不要で）消すには、システム設定 > キーボード > 入力ソース > 編集... > 「ひらがな (Nagi)」を選択 > 「−」。詳しい検証内容と、Google 日本語入力自身のアンインストーラーがなぜこの手動操作なしにエントリを消せるのかについては、docs/architecture.md の「Mozc IPC」節を参照。

**未検証（#30）: `NagiConverter`も同様にシステム設定 > 一般 > ログイン項目に残る可能性がある。** `SMAppService`によってアプリ内部から登録されており、このスクリプトが書き込んだ plist ファイルではないため、削除すべきファイルがそもそも存在しない — このスクリプトにできるのは実行中のジョブを`launchctl bootout`することだけで、`SMAppService.unregister()`に相当する処理は呼べない。アンインストール後にそこへ「Nagi」という古いエントリが残っていた場合、それが原因と考えられる。手動で削除する（上記の入力ソースと同じ「−」／右クリック操作）のが想定される対処法だが、実際の再インストール/アンインストールサイクルではまだ検証していない。

## Exit criterion

TextEdit で`nagi<Enter>`と入力すると「なぎ」が挿入される。**dev マシンで動作確認済み。**

## 登録されるまで: 3 つの静かな要件

`Nagi.app`が実際に Input Source として表示されるようになるまで（ビルドしてクラッシュせず起動する、というだけでなく）、動作実績のある IMKit バンドルとの数日がかりの二分探索が必要だった。すべての失敗モードが完全に無言だからだ — クラッシュなし、どこにもログなし、どのツールからもエラーが出ない。これが再発した場合、以下を順番に確認すること:

1. **`release`ビルドでなければならない。** `debug`ビルドには自動生成される`com.apple.security.get-task-allow`エンタイトルメントが付く。そのエンタイトルメントを持つバイナリのバンドルは Text Input Source レジストリに絶対に追加されない — `imklaunchagent`は実行時にその XPC 接続を問題なく受け付けるため、プロセスは一見健全に見える。ただ絶対に選択可能にならないだけ。
2. **`CFBundleIdentifier`（およびその下のすべての`TISInputSourceID`）が、リテラル文字列`.inputmethod.`を含んでいなければならない。** dev マシン上で見つかった動作実績のあるすべての IMKit バンドル — Apple 純正の`AinuIM.app`、Google 日本語入力、macSKK — で二分探索して確認済み。いずれもこのトークンを使っており、リテラル文字列`.inputmethod.`は`imklaunchagent`/HIToolbox の文字列テーブル内、`__cstring`セクションの`ComponentInputModeDict`/`TISInputSourceID`のすぐ近くに埋め込まれている。これを含まないバンドル ID は、他がどれだけ正しくても静かに無視される。これが、issue #1 で最初に挙がっていたよりシンプルな`com.nvleo.nagi`ではなく、バンドル ID が`com.nvleo.inputmethod.nagi`になった理由。
3. **バンドル ID（またはレジストリが参照する他の値）への変更は、フルの再起動後にしか反映されない。** ログアウトしてログインし直す — よく言われる対処法で、このリポジトリの過去のドキュメントも十分としていたもの — では再走査は強制され*ない*。フルの再起動だけが効く。`imklaunchagent`/`TextInputMenuAgent`を手動で再起動しても効果はない。

   **解決済み、M4（#30 フォローアップ）— 項目 3 は実は絶対的な要件ではなかった。** `imklaunchagent`/`TextInputMenuAgent`は自分自身のプロセス起動時に一度だけ Text Input Source レジストリを読み込み、その後は二度と再走査しない — これが「フルの再起動だけが効く」の正体で、reboot はこれらを含む全プロセスを再起動させるからそう見えていただけだった。`TISRegisterInputSource`/`TISEnableInputSource`は reboot なしでも実際にレジストリへ正しく書き込んでいる（確認済み: *新規の*プロセスから読み直すと変更が正しく反映されている）— この 2 つのエージェントが単に、自分自身が再起動するまでその変更を知らないだけ。`launchctl kickstart -k`はどちらに対しても SIP にブロックされる（「Operation not permitted while System Integrity Protection is engaged」）ため、上記の「手動で再起動しても効果はない」という結論はほぼ確実に誤りだった — その時の試みは実際には何も再起動できていなかった。`launchctl`を経由しない素の`kill -HUP`はこれらのプロセスを実際に終了させ、launchd が即座にオンデマンドエージェントとして再 spawn し、その際に変更を読み直す。`Nagi.app`はインストール後の初回起動時にこれと全く同じことを自分自身で行うようになった — `app/Sources/Nagi/InputSourceRegistration.swift`参照。これは Apple が公式にドキュメント化した挙動ではない。将来の macOS でこれが変わった場合、クラッシュではなく単に以前の reboot 必須の挙動に戻るだけ。

以下は、調査の途中ではそれぞれ有力に見えたものの、結局は関係なかった — 誰も再度たどり着かなくて済むようここに記す: ad-hoc 署名 vs 実署名（実際に Apple Development 証明書を取得して確認したが違いはなかった）、hardened runtime、バイナリ形式 vs XML 形式の`Info.plist`、thin vs universal バイナリ、`LSBackgroundOnly`、`TISInputSourceID`が`ComponentInputModeDict`の辞書キーと一致しているか異なっているか、アイコンファイルの有無、`InputMethodServerDataSourceClass`/`DelegateClass`の有無。

## M1 の Non-goals（issue から変更なし）

- Mozc IPC／実変換なし — `RomajiConverter`はプレースホルダー。
- 候補ウィンドウなし。
- パフォーマンス対応なし。
- バンドル ID（`com.nvleo.inputmethod.nagi`）とアプリアイコンは、実質的にはまだドラフト — `.inputmethod.`が必須と判明した今は機能はするが、最終版／ブランド確定版としては扱っていない。
