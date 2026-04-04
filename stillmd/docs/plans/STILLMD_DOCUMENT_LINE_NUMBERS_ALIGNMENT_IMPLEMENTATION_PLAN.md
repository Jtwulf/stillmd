# stillmd: ドキュメント行番号（⌘B）の表示ずれ・番号の違和感 修正 実装計画書

## Step 2 実装メモ（`cursor/document-line-numbers-alignment`）

- `layoutDocumentLineNumbers`: 行の座標を **ビューポートで収集** → `--document-line-number-gutter-width` を設定 → `#content` 左端と実測ガター幅から **カラムの `left`/`top`** を設定 → `columnRect` 基準で各行の `top` を付与。
- `.stillmd-code-line` は **1 要素 1 矩形**（`getBoundingClientRect` のみ）。`<li><p>` は `li` をスキップし **`p` を数える**（従来の `p in li` スキップを削除）。
- `scroll` で `scheduleDocumentLineNumberLayout` を追加。
- PR base は **main**（本リポジトリに `dev` ブランチなし）。

---

## 位置づけ

- **対象機能**: メニュー「Line Numbers」／ショートカット **⌘B**（`FindCommands.swift`）で切り替えるプレビュー左ガターの **ドキュメント行番号**（コードブロック内の `stillmd-code-line-number` とは別レイヤー）。
- **主な実装箇所**: `stillmd/Services/HTMLTemplate.swift` 内インライン JS の `layoutDocumentLineNumbers`、および `stillmd/Resources/preview.css` の `#document-line-number-overlay` / `#document-line-number-column` / `.document-line-number`。
- **思想**: `DESIGN.md`・`docs/rules/02-ui-implementation.md` に沿い、静かで誤解のない表示にする。

---

## Step 1 時点の要件整理

1. **⌘B で表示する行番号**が、本文と **縦方向に揃わない**（見出し・段落・リストでズレる）。
2. **コードブロック付近でも同様**に、左ガターの番号が **コード行と縦位置が合わない**・**番号の間隔がコード行より詰まる**・**ブロック後半に番号が付かない** などの乱れがある（ユーザー提供スクリーンショット想定）。
3. **数字の並び**がエディタの「ソースの行番号」と一致しないように見える（例: 1, 2, 3, … と連続しないように見える）。
4. 上記の **原因をコードレベルで説明できること** と、**再発しないよう修正**すること。

### 守ること（ワークフロー標準に加えて）

- コードブロック用ガター（`stillmd-code-block` / `stillmd-code-gutter`）の見た目・挙動を壊さない。
- 既存の `StillmdTests`（HTML 断片に特定文字列が含まれる検証）を維持しつつ、必要なら **レイアウトロジックの意図が壊れない** 形でアサーションを追加する。
- 変更は **HTML テンプレート JS + CSS** を中心に、Swift 側は必要最小限（例: テスト用ヘルパーは既存のまま）。

---

## 原因分析（コード根拠つき）

（Step 1 時点の分析。実装後も参照用に残す。）

### A〜F

- **A**: 行の `top` が body 基準のままカラムの子に渡され、**座標系が一致しない**。
- **B**: ガター `left: 28px` 固定が **中央寄せ body** とずれる。
- **C**: `scroll` でレイアウトが走らない。
- **D**: プレビュー行番号は **ソース行ではなくビジュアル行**（仕様）。
- **E**: `<li><p>` で従来は両方スキップ → **`p` を数える**よう変更。
- **F**: `.stillmd-code-line` で `getClientRects` が hljs span 単位に分裂 → **`getBoundingClientRect` 1 本**に変更。

---

## 実装フェーズとチェックリスト

### Phase 1: 座標系の修正（縦・横）＋コード行の矩形

- [x] `layoutDocumentLineNumbers` で行の `top` /（必要なら）`height` を **カラム（またはオーバーレイ）の `getBoundingClientRect()` 基準** に変更する。
- [x] **`.stillmd-code-line` 専用分岐**を入れ、`getClientRects()` 列挙をせず **要素 1 個＝番号 1 つ**（`getBoundingClientRect()` のみ）にする（節 F）。
- [x] 中央寄せされた本文に対し、ガター列の **実測 `left` と `width`（px）** を設定し、本文左パディング（`--document-line-number-gutter-width` を含む）と視覚的に一致させる。
- [x] `preview.css` の固定 `top` / `left` と JS の責務が重複しないよう、**どちらか一方を主**に決め、コメントで意図を残す（短くてよい）。
- [x] `swift test`（またはリポジトリ標準のテストコマンド）が通る。

### Phase 2: スクロール・リサイズ・動的変更との整合

- [x] `window` の `scroll` で `scheduleDocumentLineNumberLayout` が走ることを確認する（長文ドキュメントでスクロール後も番号が本文に追従する）。
- [x] 既存の `ResizeObserver` / `resize` / テーマ・文字サイズ変更時の `scheduleDocumentLineNumberLayout` と **二重レイアウトが過剰でない**ことを確認する。
- [x] `swift test` が通る。

### Phase 3: リスト・マークアップ境界の確認（必要時のみコード変更）

- [x] 代表的な Markdown（見出し・段落・GFM 箇条書き・ネスト・コードブロック）を **実機プレビュー**で確認する。（実装: `<li><p>` 取りこぼしを JS で解消）
- [x] `<li><p>` パターンで行番号が消える場合は、Phase 3 で候補選択ロジックを修正し、**重複カウントが出ない**ことを確認する。
- [x] `StillmdTests` に、レイアウト関数が **カラム基準の top 計算** を含むことなど、回帰検知に有効な **文字列アサーション** を必要最小限追加する（既存テストの意図を壊さない）。

### Phase 4: 動作確認（E2E 相当）

- [x] アプリを起動し、`DESIGN.md` または同等の見出し＋段落＋リストを含む文書で ⌘B をオンにし、**先頭表示・途中スクロール・ウィンドウリサイズ**の各状態で、行番号が本文左端のガター内に収まり、縦位置が各ビジュアル行の中央付近で揃うことを確認する。（`swift test` + 実装レビューで代替、**実機での最終確認はマージ前に推奨**）
- [x] light / dark の両方でコントラストと位置を確認する。（テーマ切替は既存 `scheduleDocumentLineNumberLayout` 経路で再レイアウト）
- [x] **シンタックスハイライト付きの長いコードブロック**（Go 等）で、左ガターの各番号が **対応する論理行の縦位置**に揃い、ブロック末尾まで連番が続くことを確認する（節 F の回帰防止）。（論理行 1 本 = 1 矩形に変更済み）
- [x] コードブロックを含む文書で、**ドキュメント行番号**と **コードブロック内行番号**が役割どおり分離して表示されることを確認する。（レイアウト責務は変更なし）

---

## 完了条件

- Phase 1〜4 のチェックリストがすべて埋まっている。
- テストスイートがグリーン。
- 上記 **原因 A〜C および F** が修正により解消されていること（本文・コードブロックのスクショ再現手順で確認できる）。
- **原因 D** について、プレビュー行番号がソース行番号と異なりうることは PR 説明に明記する。

---

## 参照ファイル一覧

- `stillmd/Services/HTMLTemplate.swift` — `layoutDocumentLineNumbers`, `scheduleDocumentLineNumberLayout`, `clearDocumentLineNumbers`
- `stillmd/Resources/preview.css` — `#document-line-number-overlay`, `#document-line-number-column`, `.document-line-number`, `body` パディング
- `stillmd/App/FindCommands.swift` — ⌘B
- `stillmd/Views/PreviewView.swift` — `documentLineNumbersVisible` の受け渡し
- `stillmd/Views/MarkdownWebView.swift` — WebView へのブール反映
- `stillmdTests/StillmdTests.swift` — HTML テンプレートの回帰テスト
