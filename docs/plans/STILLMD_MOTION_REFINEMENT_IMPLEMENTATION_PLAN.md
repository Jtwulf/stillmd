# stillmd モーション洗練 実装計画書

## 0. この計画書の位置づけ

- 対象: `stillmd`
- 主題: stillmd の思想に沿った、最小限のモーション導入と再整理
- 本書は **Step 2 実行用の focused plan** であり、実装そのものは含まない
- 既存方針の正本は `AGENTS.md` / `DESIGN.md` / `docs/rules/02-ui-implementation.md` / `docs/rules/04-performance.md` / `docs/rules/05-testing.md`

## 1. 背景と要件整理

ユーザー要望は次のとおり。

1. stillmd に必要に応じてアニメーションを追加したい
2. ただし、演出のための演出ではなく、stillmd の哲学に沿うことが前提
3. 特に必要だと感じている箇所は以下
   - デフォルト表示（empty status）の文言表示
   - `⌘F` による検索バーの出現・終了時

### 1.1 stillmd の判断基準

`DESIGN.md` と `docs/rules/02-ui-implementation.md` から、この計画で守るべき判断基準を固定する。

- モーションの目的は **状態変化の理解** と **滑らかさ** のみ
- 速く、短く、静かに振る舞う
- 本文より強い存在感を持つ動きは禁止
- 長い遅延、強い spring、過度な scale、バウンス、装飾的 stagger は不採用
- `Reduce Motion` を尊重し、無効化できることを前提とする
- 追加の依存ライブラリは導入しない

### 1.2 Step 2 開始時点の現状

- `RootView.swift`
  - `isReady` に対して全体 `opacity` の `.easeOut(duration: 0.16)` があり、empty state と preview が同じ責務でフェードしている
- `EmptyStateView.swift`
  - drag & drop 状態変化には `.easeOut(duration: 0.14)` がある
  - 初期表示専用のモーション責務は持っていない
- `PreviewView.swift`
  - `FindBar` の表示有無は `isFindBarPresented` で切り替えている
  - 検索バーの出現・終了に明示的な transition はない
- `FindBar.swift`
  - `onAppear` で検索フィールドに focus を当てている
  - close 時は即時消去で、query / status のリセットと視覚的退場が分離されていない

## 2. 採用方針

### 2.1 採用するモーション

#### A. Empty state の初期表示

- 文言とボタンを中心に、ごく短い `opacity` ベースの導入を与える
- 必要なら `4〜6pt` 程度の微小 `offset` を併用する
- duration は `0.16〜0.20s`
- `scale` / `blur` / `spring` / stagger は使わない

#### B. Find bar の出現

- `opacity` と小さな縦移動を組み合わせる
- duration は `0.12〜0.16s`
- offset は `-4pt` 前後から `0`
- focus はアニメーション待ちにせず、表示と同時に扱う

#### C. Find bar の終了

- 非対称 transition を許可する
- disappearance は appearance より少し短くする
- duration は `0.09〜0.12s`
- `opacity` と軽い戻りだけで十分

### 2.2 採用しないモーション

- typewriter / staggered reveal
- scale-in / pop-in
- 強い spring / bouncy transition
- 検索結果件数のカウントアップ
- 検索ハイライトの点滅
- 本文全体のフェードや再描画時のクロスフェード
- Theme / Text scale 切替時の装飾的トランジション

## 3. 実装方針

### 3.1 Empty state の責務分離

- `RootView` の全体フェード責務は外し、empty state 側にだけ限定的な導入モーションを持たせる
- preview 表示は即時とし、empty state 専用の滑らかさだけを残す
- `Reduce Motion` 有効時は即時表示へ落とせる構成にする

### 3.2 Find bar の transition 設計

- insertion:
  - opacity `0 → 1`
  - y offset `-4 → 0`
- removal:
  - opacity `1 → 0`
  - y offset `0 → -3`
- close 時は visual disappearance と query/status reset のタイミングを分離し、ちらつきを防ぐ

### 3.3 依存と性能

- 新規ライブラリ導入なし
- SwiftUI 標準の `animation` / `transition` のみで完結
- 長文 preview や検索中の応答性を悪化させない

## 4. 対象ファイル

- `MarkdownPreviewer/Views/StillmdMotion.swift`
- `MarkdownPreviewer/Views/RootView.swift`
- `MarkdownPreviewer/Views/EmptyStateView.swift`
- `MarkdownPreviewer/Views/PreviewView.swift`
- `MarkdownPreviewer/Views/FindBar.swift`
- `MarkdownPreviewerTests/MarkdownPreviewerTests.swift`

## 5. Phase 分割

### Phase 1: 現状のモーション責務整理

- [x] `RootView` の全体フェード責務を empty state から切り分ける
- [x] モーション定義を共通化し、duration / offset をコード上で一元管理する
- [x] `Reduce Motion` 前提で nil animation へ落とせる構成を作る
- [x] `swift build`
- [x] `swift test`

### Phase 2: Empty state の最小モーション

- [x] empty state の表示に短い `opacity` ベースの導入を実装する
- [x] 必要な範囲で微小 `offset` を併用する
- [x] drag & drop 時の既存アニメーションと干渉しないことを確認する
- [x] `Reduce Motion` 有効時に簡略化表示となることを確認する
- [x] `swift build`
- [x] `swift test`

### Phase 3: Find bar の出現・終了モーション

- [x] `FindBar` の表示切替に最小 transition を付与する
- [x] close 時に query / status のリセットでちらつかないことを確認する
- [x] `Esc` / close button の両方で自然に閉じることを確認する
- [x] focus 挙動が遅延しないことを確認する
- [x] `Reduce Motion` 有効時に即時表示 / 即時終了へ落とせることを確認する
- [x] `swift build`
- [x] `swift test`

### Phase 4: 回帰確認と仕上げ

- [x] モーション定義の単体テストを追加または更新する
- [x] light / dark / long markdown を含む既存体験にデグレがないことを確認する
- [x] `DESIGN.md` / `docs/rules/02-ui-implementation.md` の思想に反していないことをセルフレビューする
- [x] 計画書のチェックリストを最終状態へ更新する
- [x] `swift build`
- [x] `swift test`

## 6. テスト方針

### 6.1 自動確認

- `swift build`
- `swift test`

### 6.2 手動確認

- empty state 初期表示
- drag & drop 対象化中の empty state
- `⌘F` での検索バー表示
- close button と `Esc` での検索バー終了
- light / dark 両テーマ
- `Reduce Motion` 有効時

## 7. 完了条件

- Phase 1〜4 のチェックリストがすべて `[x]`
- empty state が stillmd らしい静けさの範囲で滑らかになる
- Find bar の出現・終了が短く自然になる
- `Reduce Motion` に対応している
- `swift build` / `swift test` が通る

## 8. Step 2 実施メモ

- `swift build` / `swift test` は各 phase 完了時と最終確認で通過した
- `./scripts/build-app.sh --release` により release `.app` 生成まで確認した
- 対話的な macOS UI 目視は headless 制約があるため、light / dark / long markdown については既存 CSS/HTML テスト、長文系プロパティテスト、差分セルフレビューで補完した
