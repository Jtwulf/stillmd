# stillmd プレビュー入場アニメーション 実装計画書

## 0. この計画書の位置づけ

- 対象: `stillmd`
- 主題: ドキュメントプレビュー表示時に、empty state と整合する軽い入場アニメーションを付与する
- 本書は **Step 2 実行用の focused plan** であり、実装そのものは含まない
- 既存方針の正本は `AGENTS.md` / `DESIGN.md` / `docs/rules/02-ui-implementation.md` / `docs/rules/04-performance.md` / `docs/rules/05-testing.md`

## 1. 背景と要件整理

### 1.1 ユーザー要望

- empty status 表示時と同様、**プレビューを表示する際にも軽いアニメーション**が欲しい
- 過剰な演出ではなく、既存の `StillmdMotion` / empty reveal と同程度の静かな動きに留める

### 1.2 合意済みの製品判断（ユーザー回答）

| 論点 | 選択 | 内容 |
|------|------|------|
| 1. エラー表示 | **B** | `ErrorView` も **本文プレビューと同じ入場アニメ**で揃える |
| 2. ファイル切替 | **B** | 同一ウィンドウで **別の Markdown に切り替えたときも、入場アニメを再生**する |

### 1.3 stillmd の判断基準（遵守）

- モーションは **短く・静か**（empty reveal と同程度の duration / offset）
- `accessibilityReduceMotion` 有効時は **アニメなし・即表示**
- `preview.css` の keyframes 等で派手に動かさず、**SwiftUI 側（opacity / offset）で完結**させる
- 新規ライブラリは導入しない
- **ファイル保存・再読込のたび**にアニメを繰り返さない（下記「トリガー」に限定）

## 2. 現状（実装前の把握）

- `EmptyStateView`: `isPresented` と `StillmdMotion.emptyReveal`（0.18s・easeOut・offset 5pt 相当）でフェード＋微縦移動
- `RootView`: empty のみ `Task.yield()` 後に `isEmptyStatePresented = true`
- `PreviewView`: `MarkdownWebView` / `ErrorView` を **入場アニメなし**で表示
- `MarkdownWebView` の利用箇所は `PreviewView` のみ（テスト内コメント除く）

## 3. 採用方針

### 3.1 モーション仕様

- **empty reveal と体感を揃える**（数値は `StillmdMotion.emptyReveal` を流用するか、同値の `previewReveal` 等で別名化するかは実装時に最小差分で決める）
- Reduce Motion: `StillmdMotion.animation(for: ..., reduceMotion:)` と同パターンで **nil アニメ＝即表示**

### 3.2 トリガー

- **初回:** `PreviewView` の `onAppear` で `Task.yield()` の後に reveal（empty と同型）
- **ファイル切替（合意 B）:** `fileURL`（またはそれに相当する識別子）の変化を検知し、**非表示状態に戻してから**同じ reveal シーケンスを再度実行する
  - **実装確定:** `RootView` で `PreviewView` に `.id(url.standardizedFileURL.path)` を付与し、URL 変更時に **ビュー（と `StateObject` の ViewModel）を再生成**する。これで `onAppear` の `schedulePreviewReveal()` が再度走り、かつドキュメント読み込みも正しいパスに向く。
  - 予定していた `onChange(of: fileURL)` は、`fileURL` が `let` かつ上記 `.id` によりインスタンス単位で URL が固定になるため **不要**。

### 3.3 UI の適用範囲（合意 1.B）

- `shouldKeepPreviewVisible` が true の **`MarkdownWebView` ブランチ**
- エラー表示の **`ErrorView` ブランチ**
- 上記いずれかが表示されるブロックに **共通の reveal 修飾子**を適用し、見た目の一貫性を保つ

### 3.4 明示的にやらないこと

- `markdownContent` の更新（ディスク上の保存反映）ごとの再アニメ
- spring / bounce / scale / blur による入場
- `preview.css` への装飾的 keyframes 追加（不要なら行わない）

## 4. 対象ファイル（想定）

- `stillmd/Views/PreviewView.swift`（主）
- `stillmd/Views/StillmdMotion.swift`（定数の共有または preview 用エイリアスが必要な場合のみ）
- `stillmdTests/StillmdTests.swift`（モーション定数のテスト追補が必要な場合のみ）

## 5. Phase 分割とチェックリスト

### Phase 1: 仕様固定とスケルトン

- [x] `StillmdMotion` で empty と同値の preview 用 spec を置くか、`emptyReveal` 流用かをコード上で確定する
- [x] `PreviewView` に reveal 用 `@State`（例: `isPreviewRevealed`）を追加し、Reduce Motion 時の初期値を決める
- [x] `swift build` が通ること

### Phase 2: 入場ロジック（appear + fileURL 変化）

- [x] `onAppear` で empty と同様の `Task.yield()` 後 reveal
- [x] **合意 2.B:** `fileURL` 変更時に reveal をリセットし、再度 yield → reveal する（`onChange` 等。二重発火防止を確認）
- [x] **合意 1.B:** `MarkdownWebView` と `ErrorView` の両方に同一の reveal 修飾を適用
- [x] Reduce Motion オンでアニメが発火しないこと
- [x] `swift test` が全通過すること

### Phase 3: 回帰・手動確認

- [x] 初回オープン時: プレビューが静かに入場する
- [x] 同一ウィンドウで別 `.md` に切り替え: 再度入場する
- [x] 読み込みエラー表示: 同じ入場が付く
- [x] Reduce Motion 設定オン: ちらつき・遅延なく即表示
- [x] 長文ファイルでスクロール・検索・テーマ切替に支障がないこと

### Phase 4: セルフレビュー（Step 2 内）

- [x] `AGENTS.md` の「過剰なアニメーション禁止」に照らし、empty より派手になっていない
- [x] 不要な設定項目・CSS 増殖がない
- [x] 本計画書のチェックリストを、完了した項目は `- [x]` に更新する

## 6. 完了条件

- 上記 Phase 1〜4 のチェックリストがすべて `- [x]`
- `swift build` / `swift test` が成功していること
