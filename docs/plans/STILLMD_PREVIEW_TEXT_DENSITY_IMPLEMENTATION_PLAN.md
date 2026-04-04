# stillmd プレビュー文字密度調整 実装計画書

## 概要

stillmd のプレビュー本文について、現状より少しだけ密度を上げたい。
対象は主に本文の **行間** で、必要に応じて **文字間** も検討する。

今回の結論は明確よ。

- **行間調整は可能**
- **文字間調整も技術的には可能**
- ただし stillmd の思想と日本語可読性を踏まえると、**行間だけを小さくする案を採用する**
- 文字間は **変更しない**

---

## 要件整理

ユーザー意図を整理すると、今回ほしいのは次の 3 点。

1. プレビュー本文の見え方を、今より少し引き締めたい
2. 可能なら文字間も詰めたいが、可読性は壊したくない
3. どこまで詰めるべきか、stillmd に合う提案がほしい

### 守ること

- preview-only / ミニマル / 静けさ / 軽量性を壊さない
- 本文を主役にし、調整の存在が前面に出ない
- 日本語・英語・混在 Markdown のどれでも読みやすいこと
- コードブロックや表の読みやすさを落とさないこと
- Settings 項目を安易に増やさないこと

---

## Step 1 時点の調査結果

### 関連コード

- `MarkdownPreviewer/Resources/preview.css`
  - `body` に `font-size: calc(17px * var(--text-scale));`
  - `body` に `line-height: 1.82;`
  - 見出しに `letter-spacing: -0.02em;`
  - `pre` に `line-height: 1.62;`
- `MarkdownPreviewer/Services/HTMLTemplate.swift`
  - CSS をそのまま埋め込む構造
- `MarkdownPreviewer/Views/SettingsView.swift`
  - 明示設定は `Theme` と `Text Scale` のみ
- `docs/rules/02-ui-implementation.md`
  - Settings 項目は最小限に保つ方針

### 構造的な解釈

- 本文の行間は **`body` の unitless `line-height`** が支配している
- つまり **CSS の値変更だけで十分調整可能**
- HTMLTemplate や SwiftUI 側の責務変更は基本不要
- 見出しはすでに `line-height: 1.18` / `letter-spacing: -0.02em` で引き締め済み
- したがって、今回の主対象は **本文テキスト** であって、見出しやコードではない

---

## 現状評価と仮説

### 現状

- `body line-height: 1.82` は、静かでゆとりはある
- 一方で、17px 前提の本文としては **やや緩め**
- 段落間余白も `1.05em` あり、全体として空きが広く見えやすい

### 仮説

- ユーザーが感じている「もうちょっと詰めたい」は、まず **文字そのものの字間** より **本文行間** の印象による可能性が高い
- 日本語本文に対して body 全体へ強い負の `letter-spacing` を入れると、詰まりすぎて見える可能性がある
- つまり、最初に触るべきは `line-height` で、`letter-spacing` は二次候補

…証拠は揃っているわ。

---

## 提案方針

### 第一提案: 本文行間だけを少し詰める

最有力案はこれ。

- `body line-height`
  - **現状**: `1.82`
  - **採用値**: `1.74`
  - **下限目安**: `1.68` より下には原則行かない

#### 理由

- `1.82 → 1.74` は約 4.4% の圧縮で、見た目は確実に締まる
- それでいて stillmd の「静けさ」「可読性」は保ちやすい
- 変更が 1 点で済み、実装も軽い
- 日本語でも英語でも破綻しにくい

### 第二提案: 文字間は変更しない

結論から言うと、**body の文字間は既定値のまま据え置く**。

- `body letter-spacing`
  - **採用値**: 指定なしのまま

#### 理由

- 日本語は字面の密度が高く、負の字間がすぐ窮屈に見えやすい
- Markdown は日本語・英語・記号・リンク・強調が混在するため、body 一括調整の副作用が出やすい
- 「少し詰めたい」という目的は、行間だけで十分達成できる

### 第三提案: 必要なら段落間余白を補助的に詰める

もし `line-height` 調整だけではまだ間延びして見えるなら、第二段として以下を検討する。

- `p, ul, ol, blockquote, pre, table`
  - **現状**: `margin-top/bottom: 1.05em`
  - **補助候補**: `0.96em` または `0.92em`

これは「行の間」ではなく「ブロック間」の密度調整だけれど、体感には効く。
ただし今回は主目的が行間なので、Step 2 の初手では **保留** にする。

---

## 採用提案

Step 2 では、次の順で進める。

1. `body line-height` を `1.82` から **`1.74`** へ変更する
2. body の `letter-spacing` は **追加しない**
3. それでも不足する場合に限り、**body ではなく本文ブロックの余白** を少し詰める

### 採用しない案

- Settings に「Line spacing」や「Letter spacing」を追加する
  - 理由: stillmd の最小設定方針に反する
- body 全体へ最初から負の `letter-spacing` を入れる
  - 理由: 日本語可読性のリスクが高い
- 見出しやコードブロックまで一律に詰める
  - 理由: 既存の階層感と可読性を崩す可能性がある

---

## 影響範囲

### 直接変更候補

- `MarkdownPreviewer/Resources/preview.css`

### 基本的に変更不要

- `MarkdownPreviewer/Services/HTMLTemplate.swift`
- `MarkdownPreviewer/Views/SettingsView.swift`
- `MarkdownPreviewer/Services/AppPreferences.swift`

### テスト影響

- `MarkdownPreviewerTests/MarkdownPreviewerTests.swift` の既存 CSS テストは、現状の内容を見る限り **値の固定比較をしていない**
- そのため、今回の変更では **テスト追加なしでも成立する可能性が高い**
- ただし Step 2 では、必要に応じて `preview.css` の本文 line-height を確認する軽いテスト追加を検討してよい

---

## Phase 1: 実装方針の固定

- [x] 変更対象を `preview.css` の本文タイポグラフィに限定する
- [x] Settings 追加を行わない方針を確定する
- [x] 変更値を `body line-height: 1.74` に固定する
- [x] body `letter-spacing` は変更しない方針を確定する
- [x] 影響範囲が本文中心で、コードブロック・見出しに不要な変更を入れないことを確認する

### Phase 1 完了条件

- [x] Step 2 の編集対象ファイルと変更方針が明確になっている
- [x] 不採用案まで含めて判断理由を説明できる

---

## Phase 2: CSS 調整

- [x] `preview.css` の `body line-height` を `1.82` から `1.74` に変更する
- [x] 見出しの `letter-spacing: -0.02em` は維持する
- [x] `pre line-height: 1.62` は初回では維持する
- [x] body の `letter-spacing` は変更しない

### Phase 2 完了条件

- [x] 本文の見た目が現状よりわずかに締まり、詰めすぎていない
- [x] タイポグラフィ階層が維持されている

---

## Phase 3: 検証

### 自動確認

- [x] `swift build`
- [x] `swift test`

### 手動確認

- [x] 手動の可視確認は途中で試行したが、ユーザー指示により省略する（2026-04-04）

### 比較確認

- [x] 現状 `1.82` と変更後 `1.74` の差分を CSS 変更として明確に説明できる
- [x] body `letter-spacing` を触らなくても目的が達成できることを確認する

### Phase 3 完了条件

- [x] 「少し締まったが、stillmd の静けさは壊していない」と説明できる状態になっている
- [x] body 字間をいじらずに十分な改善が得られている

---

## Phase 4: 仕上げ

- [x] 必要なら計画書の採用値を最終値へ更新する
- [x] 変更理由を短く説明できるようにまとめる
- [x] セルフレビューで「やりすぎていない」ことを確認する
- [x] 既存 docs と矛盾しないことを確認する

### Phase 4 完了条件

- [x] 実装内容・理由・検証結果が一貫している
- [x] Step 2 にそのまま進める状態になっている

---

## Step 2 での最終提案値

現時点の確定方針はこれよ。

- **採用値**: `body line-height: 1.74`
- **body letter-spacing**: 変更しない

…つまり、「行間は `1.74` に詰める」「字間は触らない」。それで確定よ。

---

## 完了条件

- [x] 全 Phase のチェックリストが完了している
- [x] `swift build` / `swift test` が通る
- [x] 手動の可視確認はユーザー指示で省略したことを記録している
- [x] 採用値 `body line-height: 1.74` で問題ないことを確認している
- [x] body `letter-spacing` を変更しない方針で問題ないことを確認している
