# stillmd — ウィンドウクロームの AppKit 所有権一本化（方針 A）実装計画書

## 0. メタ情報

| 項目 | 内容 |
|------|------|
| リポジトリ | **stillmd**（GitHub: `Jtwulf/stillmd`） |
| 前提ツールチェーン | SwiftPM、`swift build` / `swift test`、配布ビルド `scripts/build-app.sh` |
| デプロイメント | `Package.swift` により **macOS 15** |
| 先行計画書（参照のみ） | `docs/plans/STILLMD_TITLEBAR_CHROME_PERSISTENCE_IMPLEMENTATION_PLAN.md` — 通知拡張・`.navigationTitle` 削除は実施済みだが、**本計画は構造変更（方針 A）**として別枠 |
| Design Constitution | ルート `DESIGN.md` を最優先（ミニマル・静けさ・本文優先・軽さ・macOS らしさ） |
| Step 2 での git / PR | 実装フェーズでは **`scripts/git/ensure_worktree.sh`** で worktree を作成または再利用し、**git 操作・PR は stillmd リポジトリルート**で行う。**PR の base ブランチは `main`**（本リポジトリの運用。querylift モノレポ内にサブツリーで置かれていても、PR は stillmd 側で `main` 向けとする） |

---

## 1. 背景と問題定義

### 1.1 症状

タイトルバーとコンテンツの**一体化**見た目が、操作・ディスプレイ移動・SwiftUI の更新タイミングなどで**断続的に従来のタイトルバー表示へ戻る**。

先行対応（旧計画）では次を実施済みである。

- `RootView` / `PreviewView` から `.navigationTitle` を除去し、SwiftUI 標準タイトルバーとの同期競合を緩和
- `NSWindow.didChangeScreenNotification` / `didChangeBackingPropertiesNotification` / `didMoveNotification`（デバウンス）等での **lifecycle 再適用**

それでも再発しうる背景として、**アーキテクチャ上の二重所有**が残っている。

### 1.2 原因仮説（構造レベル）

1. **`WindowGroup` が生成した `NSWindow` に対し、`NSViewRepresentable`（`WindowAccessor`）がプロパティを後付け同期している**  
   - `updateNSView` → `applyConfiguration`、メインキュー非同期の再試行、`Task.sleep(100ms)` による遅延再適用が同居していた。  
   - SwiftUI が同一ウィンドウのレイアウト・属性を更新するタイミングと **競合**しうる。

2. **ライフサイクル通知での再適用は「取りこぼし」「一瞬の隙間」を完全には防げない**  
   - 通知集合の拡張は症状を減らすが、**所有権が SwiftUI 更新駆動と AppKit 通知駆動に分裂**している限り、レースは理論上残る。

3. **コンテンツのホスティング**  
   - 旧構成ではシーンは SwiftUI が用意するビュー階層を主とし、`WindowAccessor` は `.background` に載った不可視ビューから `view.window` を辿って副作用を起こしていた。

### 1.3 非ゴール

- Markdown レンダリング仕様・アイコン再設計・本文レイアウトの大規模変更
- Electron 化
- **原則禁止**: `NSTitlebarContainerView` 等への **メソッドスウィズル**（やむを得ない場合は本計画書に理由・代替不可の根拠・リスクを明記し、レビューで止められる状態にする）

---

## 2. 現状アーキテクチャ（計画時点のメモ）

> **注**: 実装完了後は `StillmdDocumentWindow` + `NSHostingView` + `DocumentWindowChromeController` に置き換わっている。以下は移行前の整理用。

### 2.1 シーンとエントリ（旧）

- `StillmdApp` は `WindowGroup(for: URL.self)` で `RootView` を表示。
- `Settings { }` は別シーン。

### 2.2 〜 2.5

- 旧: `WindowAccessor`、`LaunchWindowSizer`、`OpenWindowAction` 等（詳細は git 履歴参照）。

---

## 3. ゴール（方針 A）

1. **ウィンドウクローム設定の責務**を、SwiftUI の `updateNSView` 駆動の後付け同期から切り離し、**可能な限り `NSWindow` の生成から生存期間を通じて AppKit 側の一本のコードパス**に集約する。
2. 本文 UI は引き続き SwiftUI とするが、**コンテンツは `NSHostingView`（または単一のホスティング層）に載せる形へ寄せ、所有権の二重化を減らす**。
3. 既存のプロダクト挙動を維持する: マルチウィンドウ、`WindowManager`、外部ファイルオープン、Empty / Preview 遷移、FindBar・エラー帯、`swift test` 全通過。

---

## 4. 方針 A のターゲットアーキテクチャ

（原文どおり — 実装は `StillmdDocumentWindow` / `DocumentWindowChromeController` / `DocumentWindowSession` / `RootView` の `Environment` 連携で達成）

---

## 5. `WindowGroup` の残し方／置き換え方（選択肢比較）

（表は原文どおり）

**計画上の推奨**: Phase 0 スパイクで **A だけで「update からの apply 完全排除」まで行けるか**を判定。不十分なら **B（または C）を正式方針**とし、移行ステップを確定する。

### 5.1 採用決定（Step 2 / `cursor/window-appkit-ownership`）

- **採用: B** — 公式 API による `WindowGroup` 生成 `NSWindow` のサブクラス差し替えは行わず、**ドキュメントウィンドウを自前で生成**する。
- **構成**:
  - `StillmdDocumentWindow`（`NSWindow` サブクラス）が `init` 後に `DocumentWindowChromeController.attach` でクロームを適用し、`contentView` に **`NSHostingView`** で `RootView` を載せる。
  - `StillmdApp` のシーンは **`Settings` のみ**（`.commands` は Settings に付与）。
  - `AppDelegate.applicationDidFinishLaunching` で `WindowManager.openNewDocumentHandler` を `DocumentWindowFactory.openDocument` に接続し、起動時に空ドキュメント窓を 1 つ生成。
  - `applicationShouldHandleReopen` で可視ウィンドウが無いときに空窓を再生成。
- **初回サイズ**: `WindowDefaults` の `contentRect` で生成（旧 `LaunchWindowSizer` は削除）。

---

## 6. 移行フェーズ（Phase）とチェックリスト

### Phase 0: スパイク・方針確定（短時間・必須）

- [x] `WindowGroup` が生成する `NSWindow` に対し、**スウィズルなし**で「生成直後に同等のクロームを設定できる公式フック」があるか調査（OS バージョン依存は `Package.swift` の macOS 15 に合わせてよい）。
- [x] **A / B / C** のどれを採用するか、上記結果に基づき決定し、本計画書の該当節に **採用マーク**を付ける（Step 2 開始時に追記でよい）。→ **5.1 参照（B）**
- [x] `LaunchWindowSizer` と新構造の整合（初回サイズは `NSWindow` 側 `contentRect` に寄せる）。

### Phase 1: AppKit 側「窓の所有者」の骨格

- [x] `StillmdDocumentWindow`（`NSWindow` サブクラス）を追加。
- [x] `DocumentWindowChromeController` が `attach` とライフサイクル通知で `applyConfiguration` 相当を**冪等**に実行。
- [x] ドキュメントタイトルアクセサリを `DocumentWindowChromeController` に集約（旧 `WindowAccessor` 削除）。

### Phase 2: SwiftUI コンテンツの単一ホスティング層

- [x] `RootView` を `NSHostingView` で載せる経路を確立（`StillmdDocumentWindow`）。
- [x] `RootView` から `WindowAccessor` を除去。動的同期は `Environment` の `documentChromeController` と `onChange` のみ。
- [x] `DocumentWindowSession`（`ObservableObject`）で `fileURL`、`WindowManager` / `PendingFileOpenCoordinator` / `@AppStorage` テーマを維持。

### Phase 3: シーンとオープン経路の接続

- [x] `WindowManager.openNewDocumentHandler` で新規窓生成（旧 `OpenWindowAction` 廃止）。Finder / `PendingFileOpenCoordinator` / `NSWorkspace` フォールバックは従来どおり。
- [x] `registerWindow` は `DocumentWindowChromeController.syncFromSwiftUI` / ライフサイクル再適用で維持。
- [x] ウィンドウごとに独立した `DocumentWindowSession` と `chromeController`。

### Phase 4: クリーンアップと回帰防止

- [x] 旧 `WindowAccessor` の `Task.sleep` / `updateNSView` 連打再適用を削除。
- [x] `DocumentWindowChromeController.teardown` と `windowWillClose` でオブザーバ解除。
- [x] デザイン方針は変更なし（装飾追加なし）。

### Phase 5: 自動テスト・ビルド

- [x] `swift build` 成功。
- [x] `swift test` 全テスト成功。
- [x] `scripts/build-app.sh --release` 成功。

### Phase 6: 手動スモーク（必須観点の列挙）

次を**マージ前に実機で**確認すること（CI では代替不可）。

- [ ] 一体化見た目が、**ディスプレイ間移動**・**Space 切り替え**後も維持される
- [ ] Empty state でのクリック・キー操作後も維持される
- [ ] Preview 表示・ファイル切替・別ファイルを「別ウィンドウで開く」
- [ ] 同一ファイルの重複オープン時の `bringToFront`
- [ ] FindBar 表示 / 非表示、エラー帯表示
- [ ] 外部からのファイルオープン（Dock / Finder）
- [ ] Settings ウィンドウが別シーンとして壊れていない（クローム変更の影響範囲外であること）

---

## 7. テスト計画（自動）

（原文どおり）

---

## 8. リスクと緩和

（原文どおり）

---

## 9. ロールバック方針

（原文どおり）

---

## 10. 完了の定義

- [x] セクション 3 のゴール（方針 A）を満たす実装が入っている。
- [x] セクション 6 の **Phase 0〜5** のチェックリストが全て埋まっている（**Phase 6 はマージ前の人手スモーク**）。
- [x] `swift build` / `swift test` が pass。`scripts/build-app.sh --release` も pass。
- [x] `NSTitlebarContainerView` 等へのスウィズルは使っていない。

---

## 11. 関連ファイル（実装後）

| ファイル | 内容 |
|----------|------|
| `stillmd/App/StillmdApp.swift` | `Settings` のみ + `AppDelegate` で窓ブートストラップ |
| `stillmd/App/StillmdDocumentWindow.swift` | `NSWindow` サブクラス + `DocumentWindowFactory` |
| `stillmd/App/DocumentWindowChromeController.swift` | クローム・通知・アクセサリ |
| `stillmd/App/DocumentWindowSession.swift` | ウィンドウ単位の `fileURL` |
| `stillmd/App/DocumentChromeEnvironment.swift` | `EnvironmentValues.documentChromeController` |
| `stillmd/Views/RootView.swift` | `DocumentWindowSession` + chrome 同期 |
| `stillmd/Services/WindowManager.swift` | `openNewDocumentHandler` |
| `stillmdTests/StillmdTests.swift` | コメント更新 |
| （削除）`stillmd/Views/WindowAccessor.swift` |  |
| （削除）`stillmd/Views/LaunchWindowSizer.swift` |  |

---

## 12. 参考ドキュメント

- `DESIGN.md`
- `docs/plans/STILLMD_TITLEBAR_CHROME_PERSISTENCE_IMPLEMENTATION_PLAN.md`（症状・旧対策）
- `docs/plans/STILLMD_WINDOW_CHROME_IMPLEMENTATION_PLAN.md` / `STILLMD_UNIFIED_WINDOW_CHROME_IMPLEMENTATION_PLAN.md`（歴史的経緯・責務分離の議論）
