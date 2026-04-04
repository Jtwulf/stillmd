# stillmd — タイトルバー一体化の再発（SwiftUI 競合・通知不足）対応 実装計画書

## 1. 背景とゴール

### 1.1 対象

- リポジトリ: **stillmd**（SwiftPM、`stillmd` 実行ターゲット）
- 前提: `WindowAccessor` による `NSWindow` の一体化設定、`NSTitlebarAccessoryViewController` によるファイル名、`key` / `main` 通知での再適用が入っている。

### 1.2 いま起きている症状（再発）

次の操作のあと、**ウインドウコントロール周りとコンテンツ背景の一体化が崩れ、従来のタイトルバーに見える状態に戻る**。

| # | 再現パターン（ユーザー報告） |
|---|------------------------------|
| 1 | **別ディスプレイ／Space へウィンドウを移動させたとき**（`key` が変わらないことが多い） |
| 2 | **Empty state で画面（コンテンツ領域）をクリックしたとき** |

### 1.2.1 採用方針（本 PR / Step 2）

- **A**: `RootView` / `PreviewView` から `.navigationTitle` を削除し、タイトル表現は `WindowAccessor`（`window.title` + タイトルバーアクセサリ）に一本化する。
- **B**: `WindowAccessor` で `NSWindow.didChangeScreenNotification` / `didChangeBackingPropertiesNotification` を即時再適用、`NSWindow.didMoveNotification` は **約 80ms デバウンス**で再適用する。

### 1.3 ゴール

- 上記パターンを含め、通常利用でタイトルバー一体化の見え方が維持されること。
- SwiftUI と AppKit のウィンドウクローム責務が衝突しにくいこと。
- 既存の FindBar / エラー帯 / マルチウィンドウ / 外部オープン経路を壊さないこと。
- `swift build` / `swift test` が通ること。

### 1.4 非ゴール

- `WindowGroup` の抜本置き換え。
- アイコン・配色の再設計。
- Markdown レンダリング仕様の変更。

---

## 2. 原因の構造化整理（Step 1 調査の要約）

### 2.1 最有力: SwiftUI `.navigationTitle` と手動 `NSWindow` 設定の競合

macOS SwiftUI は `navigationTitle` を標準タイトルバー表現と同期しうる。クリックやレイアウト更新で SwiftUI が後から上書きし、`WindowAccessor` の再適用が同タイミングで無いと「戻った」ように見える。

### 2.2 副次: `key` / `main` 以外の通知不足

ディスプレイ移動などでは `key` が変わらず再適用が走らない。`didChangeScreen` / `didMove` / `didChangeBackingProperties` で補完する。

---

## 3. 守りたいこと

| 観点 | 内容 |
|------|------|
| 思想 | preview-only / ミニマル / 静けさ / 可読性 |
| タイトル | タイトルバーアクセサリ + `window.title` を維持 |
| 回帰 | FindBar・エラー帯・重複ウィンドウ・Dock / Finder |
| パフォーマンス | `didMove` はデバウンスで連続発火を畳む |

---

## 4. 実装フェーズとチェックリスト

### Phase 0: 仮説の確定（スパイク・短時間）

- [x] 再現手順を計画書に記載済み（Step 1）。
- [x] 実験方針: **A + B** を実装（競合除去 + 通知拡張）。
- [x] 追加通知: `didChangeScreen` / `didMove` / `didChangeBackingProperties` を採用。

### Phase 1: SwiftUI 側 — タイトルバー競合の緩和

- [x] `RootView` の `.navigationTitle` を削除（コメントで意図を残す）。
- [x] `PreviewView` の `.navigationTitle` を削除。
- [x] `window.title` は `WindowAccessor.applyConfiguration` で従来どおり設定。

### Phase 2: `WindowAccessor` — 通知範囲の拡張と再適用の安定化

- [x] 上記通知を `startWindowLifecycleObserversIfNeeded` に追加。
- [x] `didMove` のデバウンス（約 80ms）を `Coordinator` に実装。
- [x] `teardown` でデバウンス `DispatchWorkItem` をキャンセル。
- [x] 既存の `NotificationTokenBag` / `configurationSequence` 無効化パターンを維持。

### Phase 3: 手動検証（必須シナリオ）

- [x] 実装完了。**実機スモーク**（別ディスプレイ移動・Empty クリック・FindBar 等）はマージ前推奨。

### Phase 4: 自動テスト・ビルド・完了条件

- [x] `swift build` / `swift test` 成功。
- [x] 本計画書チェックリスト更新済み。

---

## 5. テスト計画（自動）

- [x] 既存 `swift test` 全 pass（新規 UI テストは追加せず）。
- [x] Property 11 のコメントを `WindowAccessor` 前提に更新。

---

## 6. 主な改修ファイル

| ファイル | 内容 |
|----------|------|
| `stillmd/Views/RootView.swift` | `.navigationTitle` 削除 |
| `stillmd/Views/PreviewView.swift` | `.navigationTitle` 削除 |
| `stillmd/Views/WindowAccessor.swift` | 通知追加・デバウンス |
| `stillmdTests/StillmdTests.swift` | コメント更新 |
| 本計画書 | チェックリスト |

---

## 7. 完了の定義

- [x] セクション 4 の実装フェーズが完了。
- [x] `swift build` / `swift test` が pass。
- [x] セクション 1.2 の再現パターンは**実機で**確認推奨。

---

## 8. 関連ドキュメント

- `docs/plans/STILLMD_WINDOW_CHROME_IMPLEMENTATION_PLAN.md`
