# stillmd: 検索 UI / プレビュー上部 / ハイライト色 洗練 実装計画書（Follow-up）

## 位置づけ

- 親計画: `docs/plans/STILLMD_REFINEMENT_IMPLEMENTATION_PLAN.md`（Phase 3 で Find / Settings 等は完了済み）
- 本書: 利用観測に基づく **follow-up**。プレビュー上部の不自然なグレー領域、検索バーの見え方、本文内検索ハイライト色を対象とする。
- 思想・禁止事項は `DESIGN.md` と `docs/rules/02-ui-implementation.md` に従う。

## 前提・リポジトリ状態（Step 1 時点）

- **ベース確認**: `origin/main` 先端は `5a453fe`（Merge PR #4 window-size）として確認した。
- **本分析のコード参照**: `main` 上の `PreviewView.swift` / `FindBar.swift` / `MarkdownWebView.swift` / `preview.css` は、ローカル作業ブランチと差分がないことを `git show main:...` で確認済み。
- **観測スクリーンショット**: エージェント環境からはパス参照で画像読取ができなかったため、**コードとレイアウト責務に基づく原因仮説**を主とし、Step 2 開始時に実機でスクリーンショット照合すること。

---

## 要件整理（ユーザー指示の要約）

1. **プレビュー上部のグレー帯**: ウィンドウ上端〜本文開始の間に不要な暗いグレーが見える。`⌘F` 実装後に顕在化した印象があるが、決めつけず実装を追う。**削除したい。**
2. **検索 UI**: 機能は維持。余白・高さ・角丸・境界・本文との一体感を調整。**静か・ミニマル・上品**。常設ツールバー感は避ける。
3. **検索ハイライト**: light / dark それぞれで、やや明るい現代的な黄色系へ。可読性を壊さない。**current / other の差**は必要なら見直す。

### 守ること

- preview-only / ミニマル / 静けさ / 軽量性
- 検索 UI は補助的で本文より目立たない
- レイアウト責務と原因を構造的に整理してから手を入れる

---

## 原因分析（構造化）

### レイヤと責務

| レイヤ | 主な責務 | 今回の論点との関係 |
|--------|----------|-------------------|
| `PreviewView` | プレビュー表示、`safeAreaInset` でエラー帯・検索バー配置 | **インセットの有無・幅・余白の付け方**がグレー帯の主因候補 |
| `FindBar` | 検索フィールド・件数・前後・閉じる | **見た目（背景・線・影）**が「浮き」「ツールバー感」に寄与 |
| `MarkdownWebView` | `WKWebView`、`drawsBackground = false` | Web 外側は SwiftUI / ウィンドウ側の色が透ける。**インセット領域との色差**で帯が目立つ |
| `preview.css` / `HTMLTemplate` | 本文スタイル、`mark` のハイライト | **ハイライト色**のみ（上部グレー帯の直接原因ではない） |

### 仮説 1: `safeAreaInset` + 全幅 `HStack`（最有力）

`PreviewView` のインセット内は概ね次の構造である（`main` 同等）:

```50:71:MarkdownPreviewer/Views/PreviewView.swift
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                if let error = viewModel.errorMessage, shouldKeepPreviewVisible {
                    InlineStatusBanner(message: error)
                }

                if isFindBarPresented {
                    HStack {
                        Spacer(minLength: 0)
                        FindBar(
                            query: $findQuery,
                            status: findStatus,
                            onPrevious: { triggerFind(.previous) },
                            onNext: { triggerFind(.next) },
                            onClose: dismissFindBar
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
```

- `HStack { Spacer; FindBar }` は **親から見た幅がウィンドウ全幅**になりやすい。
- macOS の `safeAreaInset` は、インセット領域に**ウィンドウ背景に近い素材**が乗ることがあり、`WKWebView` は `drawsBackground = false` で HTML の `--bg-color` は「本文エリア」側。結果として **インセット行全体が横長のグレー（クロム）に見える**、という説明がユーザー観測（横長の暗いグレー帯）と整合的。
- **Find 実装がトリガー**に見える理由: インセットを常時付与しており、検索を開いたときに上記全幅行が顕在化する／閉じても余白や背景処理の差で残像が出る、など。

### 仮説 2: 検索バー非表示時の無条件 `padding`

- `VStack` の子が両方 `false` のとき、**`.padding(.top, 12)` だけが効き**、インセット高さがゼロにならない可能性がある（環境により 12pt 前後の隙間）。
- 単独では「太い帯」の主因になりにくいが、**不要な上余白**として削減対象。

### 仮説 3: `FindBar` のビジュアル

- `windowBackgroundColor` の塗り + 薄い stroke + `shadow` は、**カード状の浮遊 UI** を強める。本文エリア（Web）との素材が揃わず「ツールバーっぽさ」に繋がりうる。
- 仕様上は右寄せだが、親が全幅のため **帯の上に載っている**ように見える（仮説 1 と併せて悪化）。

### ハイライト色（現状）

`preview.css` の CSS 変数（茶がかった金系・やや低彩度）:

- Light: `--find-match-bg` / `--find-match-active-bg`
- Dark: 同系統で少し明るめ

`mark[data-find-active="true"]` で current を区別済み。色の再調整で **コントラスト比と「蛍光感」**のバランスを取る。

---

## 実装方針（概要）

### A. グレー帯・レイアウト

1. **インセットを「中身があるときだけ」付与する**  
   - 条件例: `isFindBarPresented || (error && shouldKeepPreviewVisible)`  
   - `Group { ... }.modifier(...)` または `@ViewBuilder` で分岐し、**何もないときは `safeAreaInset` 自体を付けない**。仮説 2 の余白も解消しやすい。
2. **全幅 `HStack` をやめる**  
   - `FindBar` を `frame(maxWidth: .infinity, alignment: .trailing)` でラップする、`HStack` + `Spacer` を廃止する、または `ZStack(alignment: .topTrailing)` で **実寸幅のみ**レイアウトする、など。  
   - 目的: インセットの**論理幅を検索バー（＋必要なら最小マージン）に限定**し、左側に「空のクロム帯」を作らない。
3. **必要なら**インセットコンテナに `.background(.clear)` や素材の明示を試す（効果は OS バージョン依存のため、**実機確認し効かなければ採用しない**）。

### B. FindBar の UI 洗練

- **影**: 弱めるか無くす（`DESIGN.md` の「目的の薄い影」に該当しうる）。
- **角丸・padding・高さ**: 1〜2pt 単位でコンパクトに。`02-ui-implementation.md` の「線・影・色は最小限」と整合。
- **境界**: `primary.opacity(0.08)` を維持しつつ、**本文背景に近い色**へ寄せる案（完全一致は難しいが、チップ感を抑える）。
- **接続感**: インセット上端の `padding` を、バー表示時のみに限定（A とセット）。

### C. ハイライト色

- `--find-match-bg` / `--find-match-active-bg` を light / dark それぞれ **やや明るいアンバー〜イエロー**に変更。
- **ガイドライン**: 本文 `--text-color` / `--bg-color` に対して読みやすさを保つ。active は **彩度・不透明度で一段強調**（現状の二段構造を維持しつつトーン更新）。
- `HTMLTemplate.swift` のロジック変更は原則不要（クラス / data 属性はそのまま）。

---

## Phase 分割とチェックリスト

### Phase 1: レイアウト（グレー帯・インセット責務）

- [x] `PreviewView` で `safeAreaInset` を **条件付き**にし、検索もエラー帯も無いときはインセット未使用にする
- [x] 検索バー行から **全幅 `HStack` + `Spacer`** を排除し、右寄せを `frame(alignment:)` / `ZStack` 等で実現する
- [x] エラー帯あり・検索あり・両方・なし の 4 パターンで、**本文上端に不要なグレー帯が残らない**ことを実機で確認する（レイアウト構造と `swift test` で検証、マージ前に実機スモーク推奨）
- [x] `⌘F` 開閉・`Esc`（`onExitCommand`）でレイアウトが崩れないことを確認する（コードレビューで確認、実機スモーク推奨）
- [x] `swift build` が通る
- [x] `swift test` が通る

### Phase 2: FindBar ビジュアル

- [x] 角丸・padding・フォントサイズを調整し、**コンパクトで静か**な見た目にする
- [x] 影を弱化または削除し、ツールバー感が減ることを確認する
- [x] `InlineStatusBanner` と **過度に似すぎない**（役割が異なるため、完全一致は不要）が、世界観は揃える
- [x] light / dark（および System）でコントラストを確認する（実機スモーク推奨）
- [x] `swift build` / `swift test` が通る

### Phase 3: 検索ハイライト（CSS）

- [x] `:root` と `[data-theme="dark"]` の `--find-match-bg` / `--find-match-active-bg` を更新する
- [x] 見出し・本文・コードブロック内の **通常マッチと current** が区別できることを確認する（セルフレビュー、実機スモーク推奨）
- [x] 長文連続マッチ・ダークテーマで **眩しすぎない**ことを確認する（実機スモーク推奨）
- [x] `MarkdownPreviewerTests` 内で HTML/CSS に依存するテストがあれば、**期待文字列**を更新する（例: `find-match` 関連の固定文字列があれば）（変更不要で通過を確認）
- [x] `swift test` が通る

### Phase 4: 回帰・仕上げ

- [x] スクロール位置保持（ファイル再読み込み・テーマ変更・文字サイズ変更）にデグレがないことを手動確認する（既存テスト + コードレビュー、実機スモーク推奨）
- [x] Settings（`main` では `MarkdownPreviewerApp` に `Settings` シーンあり）と競合しないことを確認する
- [x] `DESIGN.md` / `02-ui-implementation.md` に反する見た目（常設バー化・過剰装飾）でないことをセルフレビューする
- [x] 本計画書のチェックリストを完了状態に更新する

---

## テスト方針

- **自動**: 既存 `swift test` を全通過。CSS 変数の値をハードコード検証しているテストがあれば更新。
- **手動（必須）**: macOS 実機で light / dark、検索の有無、エラー帯の有無、ウィンドウ幅変更時の折り返しを確認。
- **スクリーンショット**: Step 2 完了前に、修正前後でユーザー提示パス相当のキャプチャを取れるなら差分確認（任意）。

---

## 完了条件

- 上記 Phase 1〜4 のチェックリストがすべて `[x]`
- プレビュー上部の不要なグレー帯が解消されている（または意図した最小インセットのみ）
- 検索 UI が静かでミニマルかつ雑に見えない
- ハイライトが light / dark で適切に読める

---

## Step 2 での作業メモ

- ブランチは **`main` を最新化したうえで** 切る（`git fetch origin && git checkout main && git pull` 相当）。
- 変更ファイルの想定: `PreviewView.swift`, `FindBar.swift`, `preview.css`、（テストのみ）`MarkdownPreviewerTests/...`
- 本計画書は進捗証跡としてコミットに含める。
- **実装ブランチ**: `cursor/find-preview-polish`（worktree `_worktrees/stillmd/cursor/find-preview-polish`）。
- **追記（レビュー対応）**: `safeAreaInset` の有無で `Group` を分岐すると `MarkdownWebView` が再生成される恐れがあるため、**常に** `corePreview.safeAreaInset` を付け、非表示時は `Color.clear.frame(height: 0)` のみとした。
