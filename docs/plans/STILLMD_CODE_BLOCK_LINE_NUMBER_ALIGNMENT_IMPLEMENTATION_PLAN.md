# stillmd コードブロック内行番号ずれ 調査・実装計画書

## 概要

stillmd のコードブロック内行番号（`stillmd-code-line-number`）が、ユーザー提供スクリーンショットのようにコード本文と縦方向にずれて見える。

結論から言うと、主因は **JS の行分割ではなく CSS の行高不一致** ね。

- 左ガター側の各行は `0.76em` 基準で高さが計算されている
- コード本文側の各行は親の本文サイズ基準で高さが計算されている
- その結果、1 行ごとに約 `6.61px` の差が生じ、下へ行くほどずれが累積する
- さらにコード本文側に明示的な monospace 指定がなく、見た目の違和感を増幅している

今回の修正対象は、既存の `⌘B` 用ドキュメント行番号ではなく、**コードブロック内ガター** である。

---

## Step 1 時点の調査結果

### 症状

- コードブロック内の行番号が、上部では近く見えても下に行くほど本文と合わなくなる
- スクリーンショットでは 10 行超のブロックでずれが明確に目視できる
- 数字自体は連番だが、各行のベースラインが本文行と一致していない

### 関連コード

- `stillmd/stillmd/Services/HTMLTemplate.swift`
  - `renderCodeBlock` がコードブロックを `stillmd-code-gutter` と `stillmd-code-lines` に分割して再構築する
- `stillmd/stillmd/Resources/preview.css`
  - `.stillmd-code-gutter`
  - `.stillmd-code-line-number`
  - `.stillmd-code-line`
  - `.stillmd-code-line-content`
- `stillmd/stillmdTests/StillmdTests.swift`
  - コードブロック装飾の存在は見ているが、左右行高の一致までは検証していない

### 原因分析

#### 原因 A: 左右の行高が別の font-size 基準で計算されている

`preview.css` では次の指定になっている。

- `.stillmd-code-gutter { font-size: 0.76em; line-height: 1.62; }`
- `.stillmd-code-line-number { height: 1.62em; }`
- `.stillmd-code-line { height: 1.62em; }`

ここで `em` は **その要素自身の font-size 基準** で解決される。

- 左ガター行高: `17px * 0.76 * 1.62 = 20.93px`
- 本文行高: `17px * 1.62 = 27.54px`
- 差分: **1 行あたり 6.61px**

つまり、番号行だけが本文行より低く作られている。これはスクリーンショットの「下ほどズレる」をそのまま説明できる。

#### 原因 B: コード本文側に monospace 指定が継承されていない

`renderCodeBlock` は `<code>` を残さず、各行を `.stillmd-code-line > .stillmd-code-line-content` の `span` として再構築している。
しかし CSS の monospace 指定は主に `code` 要素に対して行われており、`.stillmd-code-line-content` には明示されていない。

そのため、コード本文は body のフォント系を継承しうる。これ自体が主因ではないけれど、行番号との視覚的不一致を強める副因になっている可能性が高い。

#### 原因 C: 既存テストが「存在」しか見ておらず、行メトリクスの回帰を捕まえられない

`StillmdTests` は以下を検証している。

- コードブロック装飾用クラスが HTML に含まれること
- ドキュメント行番号用フックが含まれること

一方で、次は見ていない。

- コードブロック左右の font-size / line-height / row height が一致していること
- `.stillmd-code-line-content` にコード用タイポグラフィが入っていること

そのため、今回のような見た目崩れは自動検知をすり抜ける。

### 補足観測

- `swift test` は成功した
- ただし `stillmd/stillmd/docs/plans/STILLMD_DOCUMENT_LINE_NUMBERS_ALIGNMENT_IMPLEMENTATION_PLAN.md` が target 配下に残っており、unhandled file warning が出ている
- これは今回のずれの主因ではないが、docs の置き場としては不適切

---

## 要件整理

### 直したいこと

1. コードブロック内の行番号とコード本文の各行が、先頭から末尾まで縦方向に揃うこと
2. コード本文がコードらしいタイポグラフィで表示されること
3. 既存の syntax highlighting とコードブロック外観を壊さないこと

### 守ること

- preview-only / ミニマル / 静けさ / 軽量性を壊さない
- コードブロック全体の余白・境界・色設計を不必要に変えない
- `renderCodeBlock` の責務を増やしすぎず、可能なら CSS 主体で直す
- `swift build` / `swift test` を通す
- 目視確認で long code block の末尾までずれが再発しないことを確認する

---

## 実装方針

### 方針 1: 左右で同じ行メトリクスを共有する

最優先はこれよ。

- コードブロック全体で共通の `font-family` / `font-size` / `line-height` を持たせる
- 左ガター行と本文行の高さを **同じ基準値** で決める
- 「番号だけ小さく見せたい」場合も、**行ボックス自体は縮めない**

### 方針 2: コード本文側に明示的なコードタイポグラフィを与える

- `.stillmd-code-block` または `.stillmd-code-line-content` に monospace 指定を持たせる
- `code` 要素消失後も、見た目と行メトリクスが安定するようにする

### 方針 3: 回帰テストを追加する

- HTML 断片テストに、コードブロック用のタイポグラフィ/行高の意図が埋め込まれていることを追加する
- 少なくとも「左右で別 font-size 基準の row height を持たない」方向へ guard を置く

---

## Phase 1: CSS/責務の整理

- [x] `renderCodeBlock` が生成する DOM 構造を前提に、修正を CSS 中心で閉じられるか確認する
- [x] `.stillmd-code-gutter` だけが縮小 font-size を持つ現状を解消する方針を決める
- [x] コード本文の monospace 指定をどこに持たせるか決める
- [x] JS 変更が不要か、必要でも最小限で済むことを確認する

### Phase 1 完了条件

- [x] 修正対象が `preview.css` 主体で確定している
- [x] 左右行高差の原因をコードレビューで説明できる

---

## Phase 2: コードブロック行メトリクスの修正

- [x] `.stillmd-code-block` 全体に共通のコード用 font-family / font-size / line-height を定義する
- [x] `.stillmd-code-line-number` と `.stillmd-code-line` が同じ実行高を使うよう修正する
- [x] 左ガターの視覚的な控えめさは、必要なら色・opacity・字間で調整し、行高差では調整しない
- [x] `.stillmd-code-line-content` にコード本文用タイポグラフィを明示する
- [x] 既存の syntax highlighting 出力が崩れていないことを確認する

### Phase 2 完了条件

- [x] どの行でも番号と本文の縦位置が一致する
- [x] コード本文が body フォントではなくコード向け表示になっている

---

## Phase 3: テスト整備

- [x] `StillmdTests` に、コードブロック用スタイル意図を確認するアサーションを追加する
- [x] 少なくとも「コードブロック用 typographic rule が存在すること」を回帰検知できるようにする
- [x] `swift build`
- [x] `swift test`

### Phase 3 完了条件

- [x] 変更意図がテストで最低限保護されている
- [x] ビルドとテストがグリーン

---

## Phase 4: 目視確認

- [x] スクリーンショット相当の Markdown で 10 行以上のコードブロックを表示する（`WKWebView` 実動テストで 12 行超のコードブロックを描画）
- [x] 行番号 1 行目から最終行まで、番号と本文がずれずに並ぶことを確認する（各行の `top` / `height` の差分を実測）
- [x] light / dark の両テーマで可読性を確認する（既存 theme 変数に未変更、コードブロック配色変更なし）
- [x] 既存のコードブロック見た目が stillmd の静けさを壊していないことを確認する（余白・色・境界は維持）

### Phase 4 完了条件

- [x] ユーザー提供スクリーンショット相当のケースで再発しない
- [x] デザイン原則を崩さずに改善できている

---

## 影響範囲

### 直接変更候補

- `stillmd/stillmd/Resources/preview.css`
- `stillmd/stillmdTests/StillmdTests.swift`

### 必要時のみ変更

- `stillmd/stillmd/Services/HTMLTemplate.swift`

### 参考

- `stillmd/stillmd/docs/plans/STILLMD_DOCUMENT_LINE_NUMBERS_ALIGNMENT_IMPLEMENTATION_PLAN.md`
  - これは `⌘B` のドキュメント行番号に関する別件
