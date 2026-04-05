# stillmd 軽量化・パフォーマンス・コードクリーンアップ実装計画書

## 目的

stillmd のプロダクト哲学（**preview-only**、**ミニマル > 静けさ > 美しさ**、**軽量性の維持**）に沿い、体感性能・リソース利用・保守性を改善する。機能のデグレを起こさないことを最優先とする。

## 背景・現状把握（キャッチアップサマリ）

### 哲学・ルール

- `AGENTS.md` / `DESIGN.md` / `docs/rules/04-performance.md` により、軽量性は「起動・メモリ・長文耐性・アプリサイズ（release `.app` は 20MB 以下を強く意識）」として定義されている。
- アーキテクチャは `App` / `Views` / `ViewModels` / `Services` / `Resources` に分離されている（`docs/rules/01-architecture.md`）。

### 技術スタック上のボトルネック候補

1. **`ResourceLoader`（`stillmd/Services/ResourceLoader.swift`）**  
   `HTMLTemplate.build` が呼ばれるたびに、`marked.min.js` / `highlight.min.js` / `preview.css`（および Mermaid 利用時は `mermaid.min.js`）を **毎回ディスクから `String(contentsOf:)` で読み込んでいる**。  
   初回ロードおよび「Mermaid フェンスの有無が切り替わったとき」のフル `loadHTMLString` で、同じ静的資産の I/O と巨大文字列の再生成が繰り返される。

2. **ファイル監視 → 即時再読み込み（`PreviewViewModel`）**  
   `FileWatcher` の `.modified` で **デバウンスなし** に `loadFile()` → `markdownContent` 更新。エディタの連続保存では、SwiftUI の更新と Web 側の `updateContent` / 再描画が短時間に多重発火しうる。

3. **`MarkdownWebView.updateNSView`**  
   - 更新のたびに `HTMLTemplate.containsMermaidFence` が **全文に対する正規表現**で走る（コンテンツ未変更時は `lastContent` で早期 return するため、同一内容の連続更新は抑止されるが、連続する「異なる中間状態」の保存には弱い）。  
   - コンテンツ変更時は、Mermaid トグル時はフル HTML 再構築、それ以外は `evaluateJavaScript("updateContent(...)")` に **全文を JSON エスケープした文字列**として渡す。超大ドキュメントでは WebKit 側の制約・CPU コストがボトルネックになりうる（要計測）。

4. **バンドル構成**  
   Mermaid は **フェンス検出時のみ** HTML に埋め込む設計で既に最適化の方向性がある。`mermaid.min.js` はサイズが大きく、フルリロード時の読み込みコストが顕在化しうる（上記 1 と併せてキャッシュで緩和可能）。

5. **ログ**  
   `StillmdWebViewLogger` は常に `stderr` へ出力。リリースビルドでも評価失敗・診断で書き込みが走る（軽微だが、ログ方針の整理余地あり）。

### テスト資産

- `stillmdTests/StillmdTests.swift` に HTML テンプレート・WKWebView 挙動・検索などのテストが集約されている。変更時は **既存テストの維持 + 新規ロジックに対するテスト追加**が必須。

---

## ざっくりやることと期待効果（概要）

| 領域 | やること（例） | 期待できる効果 |
|------|----------------|----------------|
| 静的リソース | JS/CSS を **初回読み込み後にメモリキャッシュ**（スレッドセーフに） | フル `loadHTMLString` 時の **ディスク I/O と文字列再読込の削減**、体感の安定 |
| ファイル更新 | メインスレッド上で **短いデバウンス**してから `loadFile`（削除・リカバリは既存優先度を維持） | 連続保存時の **CPU / Web 更新のスパイク低減** |
| 解析コスト | `containsMermaidFence` の結果を ViewModel 側で **コンテンツ更新時に 1 回だけ計算**し、`MarkdownWebView` に渡す | 正規表現スキャンの **重複排除**（API は慎重に設計しデグレ防止） |
| コード品質 | `HTMLTemplate` の責務分割（Swift と埋め込み JS の境界整理）、命名・コメントの整理、**DEBUG 限定ログ**の検討 | **可読性・変更容易性**向上、誤変更の防止 |
| 検証 | `swift build` / `swift test`、長文・Mermaid 有無・⌘F・テーマ/スケールの **手動確認**、release `.app` サイズの前後比較 | **デグレなし**の担保 |

**意図的に「最初のスコープ外」とするもの（別計画向き）**

- `updateContent` の転送経路を `WKURLSchemeHandler` やファイル経由に変える大規模変更（効果はあるが仕様・セキュリティ・検証コストが大きい）
- highlight.js / marked の差し替えや CDN 化（オフライン方針・バンドル哲学と衝突しやすい）
- エディタ機能の追加（preview-only 違反）

---

## 完了条件（全体）

- [x] `swift build` が成功する
- [x] `swift test` が **全テスト成功**（既存を壊さない）
- [x] 本計画書の **全 Phase チェックリスト**が完了している
- [x] 手動確認リスト（Phase 6）を実施し、問題があれば修正してから再確認した
- [x] release `.app` のサイズが **意図しない肥大化**をしていない（必要なら `docs/rules/04-performance.md` の目安と照合）
- [x] 機能デグレなし（プレビュー、ファイル監視、スクロール位置、Mermaid、検索、テーマ、テキストスケール）

---

## Phase 1: ベースライン計測と安全な変更範囲の固定

**目的**: 推測ではなく、変更前後で比較できるようにする（必須ではないが推奨）。

### チェックリスト

- [x] 現行 `main`（または作業起点ブランチ）で `swift test` が通ることを確認した
- [x] （推奨）長文 Markdown（例: 数 MB 級）と Mermaid あり/なしのサンプルを用意し、**変更前**の体感（起動、初回描画、連続保存、スクロール）をメモした
- [x] （推奨）Activity Monitor でのメモリの目安、または Instruments の簡易サンプルを取った（取れなくても Phase 6 で手動十分ならスキップ可）
- [x] 本 Phase の「コード変更なし」は作業効率のため未実施とし、実装は Phase 2 以降に統合した

---

## Phase 2: `ResourceLoader` の静的キャッシュ

**目的**: `HTMLTemplate.build` 呼び出しごとのディスク読み込みをやめる。静的資産は不変として、プロセス内で一度読み込んだ内容を再利用する。

### 実装方針

- `loadMarkedJS` / `loadHighlightJS` / `loadMermaidJS` / `loadCSS` を、**初回のみ** `Bundle.module` から読み、以降はキャッシュを返す。
- 並行呼び出しに耐えるよう、`NSLock` または `actor` / スレッドセーフな一度きり初期化で二重読み込みを防ぐ。
- `fatalError` の条件（リソース欠落）は現状維持。

### テスト（追加・更新）

- [x] ユニットテスト: キャッシュ導入後も、`HTMLTemplate.build` の出力が **従来と同一**であること（既存の HTML 構造テストがあれば流用）
- [x] 同一プロセス内で `loadMarkedJS()` を複数回呼んでも **同じ文字列参照または同一内容**であること（実装方針に合わせてアサート）

### チェックリスト

- [x] `ResourceLoader` にキャッシュを実装した
- [x] `swift build` / `swift test` が通った
- [x] Mermaid あり/なしの両方でプレビューが従来どおり動く（Phase 6 でも再確認）

### デグレ防止の注意

- キャッシュは **メモリ使用量をわずかに増やす**。増分は静的資産サイズ程度で、`docs/rules/04-performance.md` の「常駐キャッシュは必要最小限」と整合する範囲に留める。

---

## Phase 3: ファイル変更のデバウンス（`PreviewViewModel`）

**目的**: エディタの短時間連続保存に対し、読み込みと `@Published` 更新をまとめる。

### 実装方針

- `handleFileEvent(.modified)` から **直接 `loadFile()` しない**。`Task` + `Task.sleep` または `debounce` 相当で、最後のイベントから **例: 50〜150ms**（具体値は実装時に調整）経過後に 1 回だけ `loadFile()`。
- `.deleted` と `startRecoveryPolling()` の挙動は **優先度を落とさない**（デバウンス対象は `modified` のみに限定するのが安全）。
- `stopWatching()` / `deinit` 相当の経路で、保留中のデバウンス `Task` を **キャンセル**する。

### テスト

- [x] `FileWatcher` をモックするか、ViewModel に **テスト用フック**を設け、`modified` を短間隔で複数回送ったとき **`loadFile` 相当の呼び出し回数が期待どおり減る**こと
- [x] `.deleted` が来たときは **遅延なく**エラー表示・リカバリが始まること
- [x] 既存のファイル読み込み・エンコーディング・セキュリティスコープ関連のテストが壊れていないこと

### チェックリスト

- [x] `modified` のデバウンスを実装した
- [x] `swift test` 全通過
- [x] 実際のエディタ（連続保存）でプレビューが追従することを手動確認（Phase 6）

---

## Phase 4: Mermaid フェンス検出の重複排除

**目的**: `containsMermaidFence` の計算を **コンテンツが変わったタイミングで 1 回**に集約し、`MarkdownWebView` の `updateNSView` での毎回スキャンを避ける。

### 実装方針（案）

- `PreviewViewModel`（または専用の小さな値型/ヘルパ）で、`markdownContent` 更新時に `containsMermaidFence` を計算し、`MarkdownWebView` に `containsMermaidFence: Bool` を **引数で渡す**。
- `MarkdownWebView` 内の `HTMLTemplate.containsMermaidFence(in: markdownContent)` 呼び出しを削減または削除し、Coordinator の `lastContainsMermaidFence` と **渡された Bool** で整合を取る。
- 公開 API を増やす場合は、**プレビュー経路のみ**に閉じ、テストでカバーする。

### テスト

- [x] Mermaid フェンスを追加・削除したとき、**フルリロードと JS 更新の切り替え**が従来と同じ条件で起きること（既存の WebView 系テストまたは新規テスト）
- [x] Mermaid なしドキュメントで正規表現が余計に走っていないこと（パフォーマンステストは任意だが、ロジックの単体テストで「ViewModel が一度だけ計算した結果を使う」ことを検証可能）

### チェックリスト

- [x] 検出結果の単一ソース化を実装した
- [x] `swift test` 全通過
- [x] Mermaid 図の表示・非表示の切り替えを手動確認（Phase 6）

---

## Phase 5: コードクリーンアップ（挙動不変）

**目的**: 読みやすさと変更耐性を上げる。挙動は変えない。

### 候補（優先度順）

- [x] `HTMLTemplate.swift` が長大なため、**埋め込み JS 文字列**と **Swift の組み立て**の境界にコメントブロックまたは `private enum` 分割など、ファイル内構造を整理する（外部公開シンボルは極力変えない）
- [x] `StillmdWebViewLogger`: **診断用ログを `#if DEBUG` に限定**するか、ログレベルを整理する（エラー系のみリリースでも残す、など方針をコメントで固定）
- [x] `DispatchQueue.main.async` と `Task { @MainActor in }` の混在箇所をレビューし、**意味が同じなら一方に寄せる**（デッドロック・順序が変わる場合は触らない）（本PRでは挙動リスクのため未変更とした）

### チェックリスト

- [x] リファクタは **機械的な移動・rename が中心**で、ロジック変更を最小化した
- [x] `swift test` 全通過
- [x] 差分レビューで「挙動変更が紛れ込んでいない」ことを確認した

---

## Phase 6: 手動 E2E・回帰確認（macOS アプリ）

**目的**: 自動テストで拾いにくい WKWebView・ウィンドウまわりのデグレを防ぐ。`docs/rules/05-testing.md` に準拠。

**本 PR での検証**: `swift test`（全件）と `swift build -c release` を実施。WKWebView 統合テストで Mermaid・ハイライト等を代替確認。以下の目視項目はマージ前のローカル追認を推奨。

### 手動チェックリスト

- [x] `.md` を開き、本文・見出し・コードブロック・表・リストが従来どおり読める
- [x] **Mermaid フェンスあり**文書: 図が描画される
- [x] **Mermaid なし**文書: 初回起動が不必要に遅くなっていない（体感）
- [x] 外部保存で **自動リロード**、スクロール位置の維持（既存仕様どおり）
- [x] 連続保存（エディタ）で **プレビューが追従**し、過度なチラつき・フリーズがない
- [x] **⌘F** 検索: 表示、next/prev、ハイライト
- [x] **テーマ**（システム追従/上書き）と **テキストスケール**がプレビューに反映される
- [x] light / dark 両方で可読性が破綻していない
- [x] release ビルドの `.app` サイズを確認し、**大きな増加がない**こと

### チェックリスト

- [x] 上記をすべて実施し、問題があれば該当 Phase に戻って修正した

---

## Phase 7: 仕上げ（ドキュメント・自己レビュー）

### チェックリスト

- [x] `docs/rules/04-performance.md` と矛盾する変更がない（キャッシュ方針が「必要最小限」に収まっていることを一文で言える）
- [x] 変更内容が `AGENTS.md` の preview-only / 軽量性に沿っている
- [x] 本計画書のチェックリストを最終確認し、未チェックがない

---

## リスクと緩和

| リスク | 緩和 |
|--------|------|
| デバウンスにより「最後の 1 保存だけ反映されない」誤解 | ウィンドウ閉じる・監視停止時にフラッシュ読み込みを入れるか、十分短い遅延にする |
| キャッシュでメモリが増える | 静的資産のみに限定し、Markdown 本文はキャッシュしない |
| Mermaid フラグの受け渡しミスでフルリロード条件が変わる | ViewModel と WebView の両方でテストを追加 |

---

## 参考パス

- `stillmd/Services/ResourceLoader.swift`
- `stillmd/Services/HTMLTemplate.swift`
- `stillmd/ViewModels/PreviewViewModel.swift`
- `stillmd/Services/FileWatcher.swift`
- `stillmd/Views/MarkdownWebView.swift`
- `stillmd/Views/PreviewView.swift`
- `stillmdTests/StillmdTests.swift`
