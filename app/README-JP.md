🇯🇵 日本語 ・ [🇺🇸 English](README.md)

# app — M1: 文字確定できる空の IME

IMKit のスケルトンをシステム設定に登録し、TextEdit にテキストを書き込めるようにする。まだ変換はしない（それは M2 で、`MozcClient`経由 — [`poc/`](../poc) 参照）— ここでは nagi が入力モードを保持できることだけを証明する。

## ここにあるもの

- `Package.swift` — 外部依存なしのプレーンな SwiftPM 実行可能ターゲット。`Cocoa` / `InputMethodKit`はシステムフレームワークで暗黙的にリンクされる。
- `Sources/Nagi/main.swift` — プロセスのエントリーポイント。`Info.plist`で宣言された接続名の下に`IMKServer`を立ち上げ、アクセサリ（Dock アイコンなし）アプリとして実行する。
- `Sources/Nagi/NagiInputController.swift` — `IMKInputController`のサブクラス。入力されたローマ字をバッファし、`setMarkedText`で下線付きの未確定文字として表示する。Enter で`insertText`により変換後のひらがなを確定する。
- `Sources/Nagi/RomajiConverter.swift` — 小さな貪欲法によるローマ字→ひらがな変換テーブル。意図的に Mozc ではない — 理由はファイルヘッダー参照。
- `Resources/Info.plist` — IMKit 登録用のメタデータ（接続名、コントローラークラス、宣言された入力モード）。google/mozc 自身の`mac/Info.plist`、macSKK、Apple の純正バンドル`/System/Library/Input Methods/AinuIM.app`と照合した。間違えやすいキーを正しく設定するためだ。単に「キーを正しく設定する」以上の手間がかかっている（詳細は下記「登録されるまで」参照）。
- `Resources/InfoPlist.strings` — 入力ソースピッカー用の表示名。これがないと、macOS は"Nagi"/"ひらがな"の代わりに生の`TISInputSourceID`文字列を表示する。
- `Resources/icons/nagi.tiff` — メニューバー／入力ソース一覧のモードアイコン。本物のアートワークで、`scripts/icons/generate.py` から生成する（`scripts/build-icons.sh` 参照）。Apple 純正 IME（AinuIM.app の Ainu.tiff 等）と同じく、透明の穴でグリフを抜く形式にした。`TISIconIsTemplate`（Info.plist 参照）が正しく色をティントするために必須だ（#35）。

## `.xcodeproj`がない理由

[`poc/`](../poc) と同じ理由: この環境には Xcode の Command Line Tools はあるが、Xcode GUI はない。プロジェクトは M0 以降 SwiftPM ベースになっている。IMKit の`.app`に Xcode は不要だ。正しい`Info.plist`キーを持つバンドル内に、有効な Mach-O バイナリがあればよい。`scripts/build-app.sh`が素の`swift build`の出力から手作業でバンドルを組み立てる。

M1 の途中で Xcode 自体は dev マシンにインストールされることになった。無料の Apple ID 開発証明書を得るためで、行き詰まった署名関連の仮説を追っていたときのことだ（下記参照）。ただしビルド自体は今でも Xcode を使わない。

誰かが Xcode GUI 環境でこのプロジェクトを引き継ぎ、M3 向けによりリッチな Interface Builder／アセットカタログ機能を使いたくなったときに見直すこと。

## ビルド

```sh
./scripts/build-app.sh          # release（デフォルト）
./scripts/build-app.sh debug    # コンパイルはできるが、絶対に登録されない — 下記参照
```

`.build-app/Nagi.app`を生成する（デフォルトで ad-hoc 署名）。`security find-identity`のハッシュを`CODESIGN_IDENTITY`に設定すれば実署名も可能だが、必須ではない。ad-hoc で十分動作する。

## ビルド済みインストール（curl ワンライナー）

フルの開発環境（Xcode、Bazel、...— 上記「ビルド」参照）なしで Nagi を試したい場合:

```sh
curl -fsSL https://github.com/nv-leo/nagi/releases/latest/download/install-nagi.sh | bash
```

`scripts/install-nagi.sh`が最新リリースの`Nagi.zip`をダウンロードし、展開して`/Library/Input Methods/`にインストールする（システムフォルダのため、管理者パスワードを 1 回求める）。その後 Nagi を起動する。スクリプトの中身を確認してから実行したい場合は、ダウンロード→確認→実行という流れも可能:

```sh
curl -fsSLO https://github.com/nv-leo/nagi/releases/latest/download/install-nagi.sh
less install-nagi.sh
bash install-nagi.sh
```

この`Nagi.zip`を生成するのは`scripts/build-release-zip.sh`（`ditto`を使用）。単純な`zip`と違い、署名済み`.app`バンドルが zip 往復後も保つべきもの — 拡張属性・リソースフォーク・コード署名自体 — を壊さずに保持できる。

### なぜ`.dmg`ではないのか

このセクションの以前のバージョンでは、ドラッグ＆ドロップの`.dmg`を配布していた（#30 で議論、[この r/opensource のスレッド](https://www.reddit.com/r/opensource/comments/1ku0zv0/) のご指摘に感謝 — さらに前は`.pkg`案だった）。最初は`Nagi.app`を`/Library/Input Methods/`へのシンボリックリンクにドラッグする方式にした。しかし実機検証で、Finder のドラッグ＆ドロップが管理者パスワードダイアログへエスカレーションするのは固定の許可リストに限られると判明した。それ以外へのドロップはサイレントに失敗する（[この Apple Developer Forums のスレッド](https://developer.apple.com/forums/thread/712148) 参照）。そこでダブルクリックで完結する`Install Nagi.app`インストーラー方式に切り替えた。しかしどちらも、さらなる実機検証（今度はローカルビルドではなく実際のブラウザダウンロード経由）で、回避不能な壁にぶつかって断念した。

**このリポジトリの背後に Apple Developer Program のメンバーシップ（Developer ID）は存在しない。** そのため Nagi が配布するものはすべて ad-hoc 署名（`codesign --sign -`）であり、Developer ID 署名でも公証済みでもない。

**macOS 15（Sequoia）以降 — 26（Tahoe）を含む — では、quarantine 済みの *ad-hoc 署名* アプリに対して Gatekeeper に GUI での回避手段が一切存在しない。**

Developer ID 署名・未公証のアプリなら見慣れた「開発元を確認できません」というバイパス可能なプロンプトが出る。だが ad-hoc 署名の場合は違う。代わりに macOS は`"<app>"は壊れているため開けません`と表示し、選択肢は「ゴミ箱に入れる」のみになる。Control-click → 開く は何も起こさない。システム設定 → プライバシーとセキュリティにも「このまま開く」ボタンは現れない。Gatekeeper がブロックした評価そのものを記録しないため、上書き許可の選択肢を提示しようがないからだ。

ダウンロードした`.dmg`に付く quarantine フラグが、マウント時に`quarantine`マウントオプションを付与させる原因だ。それがボリューム内のすべての ad-hoc 署名アプリを起動不能にする。

`.dmg`を開く前に`xattr -d com.apple.quarantine`で手動で剥がせば回避できる。だがこれも結局 Terminal を使う手順であり、ドラッグ＆ドロップ／ダブルクリックのインストーラーが目指していたものを損なってしまう。

curl はブラウザと違い、ダウンロードしたものに`com.apple.quarantine`を付与しない。そのため`install-nagi.sh`は配布経路のレベルで問題自体を回避する。取得するものが一切 quarantine されないので、上記の ad-hoc／未公証の壁がそもそも発動しない。

`xattr`での回避策すら不要になる — `.dmg`方式では避けられなかったあの 1 行すら必要ない。これは同じく個人開発の macOS IME である[SwiftyGyaim](https://github.com/tanabe1478/SwiftyGyaim) が同じ理由で行っているのと同じ署名面のトレードオフだ。

Developer ID 署名・公証済みのリリース（macSKK/AquaSKK/azooKey-Desktop に合わせる、いずれも#30 で調査済み）はまだ roadmap（M4）上にある — 有償の Developer ID が先に必要。

ワンライナーでのインストールは、ソースからのビルドと違って 3 つの自己登録に支えられている。`Nagi.app`は初回起動時に`SMAppService`経由で自分自身の`NagiConverter` LaunchAgent を登録する（`app/Sources/Nagi/ConverterServiceRegistration.swift`参照）。

M4 の #30 フォローアップとして自分自身を Text Input Source としても登録する（`app/Sources/Nagi/InputSourceRegistration.swift`、下記「登録されるまで」参照）。

さらに`Uninstall Nagi.app`を`/Applications/`へ自分で配置する（#33 フォローアップ、`app/Sources/Nagi/UninstallerDeployment.swift`）。このいずれもインストーラースクリプト側で代行する必要はない。

ただしこの 3 つとも、実際に使えるようになるのは次回ログイン時からだ（同じく下記「登録されるまで」参照）。フルの reboot は不要になったものの即時ではない。

**`install-nagi.sh`自体が途中で失敗した場合**（例: ダウンロード中にネットワークが切れた）、Nagi はインストールされておらず片付けるものも無い。ワンライナーを再実行すればよい。`Nagi.app`の配置後、Nagi が一度も起動する前に失敗した場合は、`Uninstall Nagi.app`も`/Applications/`へ配置されない。その場合は Finder で`/Library/Input Methods/Nagi.app`を手動削除するか、リポジトリを clone した人なら`scripts/uninstall-ime.sh`を使うこと。

## インストール（ソースから）

```sh
./scripts/install-ime.sh                  # ~/Library/Input Methods/
./scripts/install-ime.sh release --system # /Library/Input Methods/（sudo）
```

**その後、手動で:**

1. **`Nagi.app`を一度起動する** — Finder でダブルクリックするか、`open "/Library/Input Methods/Nagi.app"`。これにより自己登録がトリガーされる（`app/Sources/Nagi/InputSourceRegistration.swift`、#30 フォローアップ）。

   作業中の画面の上に、その場でログアウトを提案するアラートダイアログが出るはずだ（`app/Sources/Nagi/FirstRunPrompt.swift`）。

   バックグラウンド通知に頼らずこの方式にしているのは理由がある。Nagi のように Dock アイコンもウィンドウも持たない`LSUIElement`アプリでは、`UNUserNotificationCenter`の許可取得が不安定なためだ。`app/Sources/Nagi/ConverterServiceRegistration.swift`で対策済みだが、それでも「Notifications are not allowed for this application」で失敗することを実機確認済みだった。

   アラートで「今すぐログアウト」を選ぶか、「あとで」を選んで手順 2 を自分で行うこと。
2. **一度ログアウトしてログインし直す**（手順 1 のアラートで既に済んでいればスキップ）。この時点ではまだ何も表示されない — システム設定の入力ソース一覧にも、メニューバーにも、変換にも。登録自体は既に成功しているにもかかわらずだ。

   なぜすべてが次回ログインまで反映されないかは、下記「登録されるまで」参照。フルの再起動は不要で、ログアウトだけで十分だ。Google 日本語入力など他のサードパーティ製 macOS IME も共通して必要とする一度限りの手順であり、Nagi 固有の制約ではない。
3. システム設定 → キーボード → 入力ソース を確認する。「+」を押さなくても「Nagi」が日本語の下に並んでいるはずだ。他の日本語 IME（Google 日本語入力、macSKK など）がインストールされている場合、「ひらがな」という名前のエントリが複数あることがある。モードアイコンで見分けること。それでも出てこない場合は、編集... → 「+」→ 日本語の下の「Nagi」を探す → 追加、にフォールバックする。
4. メニューバーの入力メニューから切り替える。
5. TextEdit で`nagi`と入力して Enter。

## アンインストール

```sh
./scripts/uninstall-ime.sh                  # ~/Library/Input Methods/
./scripts/uninstall-ime.sh --system         # /Library/Input Methods/（sudo）
./scripts/uninstall-ime.sh --all            # 両方
```

上記の curl ワンライナー経由でインストールした場合は`/Library/Input Methods/`なので`--system`を使うこと。あるいは Applications フォルダの`Uninstall Nagi.app`をダブルクリックすれば Terminal 不要（上記「ビルド済みインストール」参照）。

`Nagi.app`を削除し、`NagiConverter` LaunchAgent を停止し、システム設定の入力ソースから Nagi のエントリも消す。手動操作も reboot も不要だ（#33: `scripts/dmg/nagi-tis-disable.swift`をその場でコンパイル・実行している。GUI 版`Uninstall Nagi.app`と同じヘルパーだ）。`swiftc`（Xcode Command Line Tools）が必要で、それが無い場合は入力ソースのエントリが以前の挙動にフォールバックする（切り替え不可のまま残留し、reboot 不要で消すにはシステム設定 > キーボード > 入力ソース > 編集... > 「ひらがな (Nagi)」を選択 > 「−」、または reboot）。`uninstall-ime.sh`自体は#30 のインストール/アンインストール対応まで存在しなかった — `install-ime.sh`にはそれまで対になるスクリプトがなかった。

**検証済み（#30 フォローアップ）: `NagiConverter`はシステム設定 > 一般 > ログイン項目に目に見えるゴーストエントリを残さない。** `SMAppService`によってアプリ内部から登録されており、このスクリプトが書き込んだ plist ファイルではない。そのため削除すべきファイルがそもそも存在しない。このスクリプトにできるのは実行中のジョブを`launchctl bootout`することだけで、`SMAppService.unregister()`に相当する処理は呼べない。このメソッドは登録元アプリ自身の実行中プロセスからしか呼べないインスタンスメソッドだ。外部スクリプトが他アプリの`SMAppService`登録を解除できる公開 API は存在しない。

開発機で確認済み: アンインストール直後は`Nagi`・`NagiConverter`とも`sfltool dumpbtm`レベルでは一時的に残存していた（`Nagi`は`disabled`に、`NagiConverter`は`enabled`のまま）。だがシステム設定のログイン項目 UI 上には一度も表示されず、手動操作なしで数分以内に`dumpbtm`の出力からも消えた。ユーザーに見える形での残留は確認されなかった。

## Exit criterion

TextEdit で`nagi<Enter>`と入力すると「なぎ」が挿入される。**dev マシンで動作確認済み。**

## 登録されるまで: 3 つの静かな要件

`Nagi.app`が実際に Input Source として表示されるまでには、時間がかかった。ビルドしてクラッシュせず起動する、というだけでは足りない。動作実績のある IMKit バンドルとの、数日がかりの二分探索が必要だった。すべての失敗モードが完全に無言だからだ — クラッシュなし、どこにもログなし、どのツールからもエラーが出ない。これが再発した場合、以下を順番に確認すること:

1. **`release`ビルドでなければならない。** `debug`ビルドには自動生成される`com.apple.security.get-task-allow`エンタイトルメントが付く。そのエンタイトルメントを持つバイナリのバンドルは、Text Input Source レジストリに絶対に追加されない。`imklaunchagent`は実行時にその XPC 接続を問題なく受け付けるため、プロセスは一見健全に見える。ただ絶対に選択可能にならないだけだ。
2. **`CFBundleIdentifier`（およびその下のすべての`TISInputSourceID`）が、リテラル文字列`.inputmethod.`を含んでいなければならない。**

   dev マシン上で見つかった、動作実績のあるすべての IMKit バンドルで二分探索して確認済みだ。対象は Apple 純正の`AinuIM.app`、Google 日本語入力、macSKK。いずれもこのトークンを使っている。

   リテラル文字列`.inputmethod.`は`imklaunchagent`/HIToolbox の文字列テーブル内、`__cstring`セクションの`ComponentInputModeDict`/`TISInputSourceID`のすぐ近くに埋め込まれている。これを含まないバンドル ID は、他がどれだけ正しくても静かに無視される。

   これが、issue #1 で最初に挙がっていたよりシンプルな`com.nvleo.nagi`ではなく、バンドル ID が`com.nvleo.inputmethod.nagi`になった理由だ。
3. **バンドル ID（またはレジストリが参照する他の値）への変更は、フルの再起動後にしか反映されない。** ログアウトしてログインし直す — よく言われる対処法で、このリポジトリの過去のドキュメントも十分としていたもの — では再走査は強制され*ない*。

   フルの再起動だけが効く。`imklaunchagent`/`TextInputMenuAgent`を手動で再起動しても効果はない。

   **部分的に解決、M4（#30 フォローアップ）— フルの「reboot」は不要になったが、「ログアウト＆再ログイン」はまだ必要。** 詳しい経緯は[issue #33](https://github.com/nv-leo/nagi/issues/33) 参照。

   要約すると、`Nagi.app`は`com.apple.HIToolbox`設定ドメインの`AppleEnabledInputSources`配列に、自分自身のエントリを`CFPreferencesSetValue`で直接追記する（`app/Sources/Nagi/InputSourceRegistration.swift`参照）。

   System Settings の入力ソース一覧・メニューバーの入力メニュー・変換は、いずれも最終的にはこの配列の内容が正しいことに依存している。ただし、これを書いただけでは**今のログインセッションでは 3 つのどれにも反映されない**ことを確認した。確認は、一度も登録したことのない真にフレッシュな状態で行った。System Settings は新規に開き直しても、一度終了して再度開いても、Nagi を表示しなかった。

   実機での大規模な逆アセンブル調査をした。HIToolbox の非公開関数を解析し、Kotoeri ・ AinuIM ・素のキーボードレイアウトとの差分テストを重ねた。

   その結果、System Settings もメニューバーの入力メニュー（`_TSMCopySelectableInputSourcesInUIOrder()`から構築）も、`AppleEnabledInputSources`を直接読んでいるのではないと判明した。

   どちらも HIToolbox が`UpdatePBInputSourcesInUIOrder`で materialize する**ログインセッション単位のペーストボード**を読んでいる。

   このペーストボードは、Nagi が書き込む「Keyboard Input Method」種別の親エントリ単体を、Kotoeri の実エントリが既に持っている「Input Mode」種別の子エントリへと展開する。ただしこの展開処理は、ログイン時にしか起きない。

   `imklaunchagent`/`TextInputMenuAgent`を`killall -HUP`で再起動する処理が以前のバージョンにはあったが、撤去した。エージェント自体は再起動できても、ペーストボードの中身までは更新されないからだ。効果ゼロでコスト（入力切り替えの一瞬のハングアップ）だけが残っていた。

   `TISEnableInputSource`/`TISDisableInputSource`はより有望に見えた。初回呼び出し時には本物のユーザー許可ダイアログを表示する。だが Nagi 自身のバンドルやそのひらがなモードに対して呼んでも、許可の前後を問わずサイレントな no-op だった（`OSStatus noErr`、何も変化しない）。実際にペーストボード再構築を強制できた唯一の方法は、無関係な既存の入力ソース（キーボードレイアウトなど）を enable/disable することだった。ただしインストール処理の中でユーザーの実際の設定を勝手に操作するのは適切ではない。

   `NagiConverter`の`SMAppService`登録（`app/Sources/Nagi/ConverterServiceRegistration.swift`）も同じ形の制約を抱えている。`register()`は即座に`.enabled`（承認済み）を返すが、**今のログインセッションの launchd には次回ログインまでロードされない**。これもアプリ内から強制する手段はない。

   結果として、インストール → 一度起動 → 一度ログアウト・ログインし直す、という流れになる。これで System Settings ・メニューバー・変換のすべてがまとめて使えるようになる（手動での「+」操作は不要）。**これは Nagi 固有のバグではない** — Google 日本語入力や macSKK 自身のインストールガイドにも、同じ一度限りの要件が明記されている。

以下は、調査の途中ではそれぞれ有力に見えたが、結局は関係なかった項目だ。誰も再度たどり着かなくて済むよう、ここに記す。

- ad-hoc 署名 vs 実署名（実際に Apple Development 証明書を取得して確認したが違いはなかった）
- hardened runtime
- バイナリ形式 vs XML 形式の`Info.plist`
- thin vs universal バイナリ
- `LSBackgroundOnly`
- `TISInputSourceID`が`ComponentInputModeDict`の辞書キーと一致しているか異なっているか
- アイコンファイルの有無
- `InputMethodServerDataSourceClass`/`DelegateClass`の有無

## M1 の Non-goals（issue から変更なし）

- Mozc IPC／実変換なし — `RomajiConverter`はプレースホルダー。
- 候補ウィンドウなし。
- パフォーマンス対応なし。
- バンドル ID（`com.nvleo.inputmethod.nagi`）とアプリアイコンは、実質的にはまだドラフトだ。`.inputmethod.`が必須と判明した今は機能するが、最終版／ブランド確定版としては扱っていない。
