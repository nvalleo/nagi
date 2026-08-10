<p align="center">
  <img src="docs/images/icon.png" width="120" height="120" alt="Nagi のアイコン — 陽と、静まる 2 本の波">
</p>

<h1 align="center">nagi</h1>

<p align="center">
  macOS 向けの、モダンで軽量な日本語 IME — おなじみの変換品質を、<br>
  ようやくこの時代らしくなった候補ウィンドウで。
</p>

<p align="center">
  🇯🇵 日本語 ・ <a href="README.md">🇺🇸 English</a>
</p>

<p align="center">
  <img alt="status: pre-alpha" src="https://img.shields.io/badge/status-pre--alpha-lightgrey">
  <img alt="platform: macOS" src="https://img.shields.io/badge/platform-macOS-black">
  <img alt="license: Apache 2.0" src="https://img.shields.io/badge/license-Apache%202.0-blue">
</p>

---

## 目次

- [nagi とは](#nagi-とは)
- [インストール](#インストール)
- [アンインストール](#アンインストール)
- [なぜまた日本語 IME を作るのか](#なぜまた日本語-ime-を作るのか)
- [やらないこと](#やらないこと)
- [アーキテクチャ概観](#アーキテクチャ概観)
- [パフォーマンス目標](#パフォーマンス目標)
- [開発](#開発)
- [ライセンス](#ライセンス)

## nagi とは

`nagi` は、Mozc 変換エンジン（Google 日本語入力のオープンソース版コア）を
再利用し、その上にネイティブな SwiftUI 製の候補ウィンドウを乗せた macOS 用
入力メソッドです。エンジンはアプリバンドルの中に同梱されているため、
別途 Google 日本語入力をインストールする必要はありません。

名前の由来は「凪」— 風がやみ、海面が静まる、あの瞬間のことです。
これがそのまま、目指している入力体験でもあります: 軽く、静かで、
予測可能。

## インストール

[最新の Release](https://github.com/nv-leo/nagi/releases/latest) から
`Nagi-<version>.dmg`をダウンロードして開き、中の`Input Methods`
エイリアスに`Nagi.app`をドラッグしてください。`Nagi.app`を一度だけ
開く（macOS が「開発元を確認できません」と警告しますが、
Control-click → 開く、で通ります）— これで準備完了です。システム設定 >
キーボード > 入力ソースに出てくるまでに再起動は不要です。`nagi`は
pre-alpha で未署名・未公証（有償の Apple Developer ID がまだないため）
— `.dmg`内の`README.txt`に、macOS がより頑固に開くのを拒む場合の
対処法も含めたフルの手順があります。

自分でビルドしたい場合は、[`app/README.md`](app/README.md)（英語）に
ソースからのビルド手順があります（`./scripts/build-dmg.sh`で同じ
`.dmg`が作れます）。

## アンインストール

インストール時と同じ`.dmg`に入っている`Uninstall Nagi.app`を
ダブルクリックしてください。確認と管理者パスワードの入力の後、
Nagi 本体・バックグラウンドプロセス・入力ソースのエントリまで
まとめて削除します — Terminal は不要です。「日本語」の下に空欄の
行が残ることがありますが実害はなく、アンインストーラーが
再起動を提案します（強制ではありません）。

ソースからビルドした場合は、`./scripts/uninstall-ime.sh --system`
でファイル・プロセスの削除ができます。詳細は
[`app/README.md`](app/README.md)（英語）参照。

## なぜまた日本語 IME を作るのか

直接名前を挙げる価値がある製品がひとつあります。`nagi` は、まさに
それとは別のフロントエンドであることを目指して存在しているからです:
**Google 日本語入力**、macOS 向けの公式な Mozc ベース IME です。`nagi` は
Google 日本語入力とまったく同じ変換エンジン — Mozc — を使っており、
違いは表面の UI だけにあります:

| | Google 日本語入力（公式） | **nagi** |
|---|---|---|
| 変換エンジン | Mozc | Mozc（同梱） |
| 候補 UI | レガシー（〜2010 年頃） | モダン、SwiftUI |
| 追加インストール | — | 不要 |
| 予測可能性 | 高い | 高い |
| メモリ使用量 | 少ない | 少ない |

`nagi` はエンジンより賢くなろうとしているわけではありません —
エンジンはすでに十分良いものです。目指しているのは、macOS に欠けて
いた、Mozc のためのフロントエンドになることです。

## やらないこと

- ニューラル／LLM ファーストの IME**ではありません**。Magic Conversions
  がほしければ azooKey を使ってください。
- エンジニア特化の IME**ではありません**。ライター、オフィスワーカー、
  学生など、日本語を打つ誰にとってもしっくりくることを目指します。
- Mozc のフォーク**ではありません**。upstream の `google/mozc` を
  追随し、置き換えるのはレンダラーだけです。
- v1 時点ではクロスプラットフォーム**ではありません**。Linux ・ Windows
  は、macOS 版のコアが安定してからの長期ロードマップ上にあります。

## アーキテクチャ概観

（日本語と英字が混在する罫線図は等幅表示が崩れやすいため、英語版と同じ図を掲載しています）

```
┌────────────────────────────────────┐
│ macOS app (Swift, IMKit)           │
│   ┌────────────────────────────┐   │
│   │ IMKInputController         │   │
│   │  → routes keys, commits    │   │
│   └────────────┬───────────────┘   │
│                │                   │
│   ┌────────────▼───────────────┐   │
│   │ Candidate window (SwiftUI) │   │
│   │  NSPanel, non-activating   │   │
│   └────────────┬───────────────┘   │
│                │                   │
│   ┌────────────▼───────────────┐   │
│   │ Mozc IPC client (Swift +   │   │
│   │ SwiftProtobuf)             │   │
│   └────────────┬───────────────┘   │
└────────────────┼───────────────────┘
                 │ Mach IPC
┌────────────────▼───────────────────┐
│ mozc_server (bundled, C++,         │
│ rebranded "NagiConverter")         │
│   converter, dictionary, learning  │
└────────────────────────────────────┘
```

詳細は [docs/architecture.md](docs/architecture.md)、マイルストーン計画は
[docs/roadmap.md](docs/roadmap.md) を参照してください（いずれも英語）。

## パフォーマンス目標

- キー入力 → 候補ウィンドウ描画: 目標 **16 ms 以内**（1 フレーム）、
  上限 **50 ms 以内**。
- 常駐メモリ（アプリ＋同梱の `mozc_server`）: 通常 **150 MB 以下**。
- コールドスタート（ログイン後の最初のキー入力）: 初回描画まで
  **300 ms 以内**。

これらは目標であって約束ではありません。設計上の選択がこの目標を
脅かしていないか気づくために存在しています。

## 開発

Swift↔Mozc IPC の M0 時点の実証実験については
[`poc/README.md`](poc/README.md)（英語）、IMKit アプリ本体のビルド・
インストール・`scripts/install-ime.sh` の流れについては
[`app/README.md`](app/README.md)（英語）を参照してください。

## ライセンス

Apache License 2.0 — 詳細は [LICENSE](LICENSE) を参照してください。
Mozc の BSD 3-Clause ライセンスとの互換性と、明示的な特許許諾があることから
選定しました。

Mozc 自体は元の BSD 3-Clause ライセンスのままです。同梱している
`mozc_server` バイナリおよび Mozc 由来のコードには、そのライセンス表記が
付されます。
