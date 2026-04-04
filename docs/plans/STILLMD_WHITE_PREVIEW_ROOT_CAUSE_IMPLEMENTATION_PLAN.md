# stillmd — 白いプレビュー根本原因切り分け・修正 実装計画書

## 0. メタ情報

| 項目 | 内容 |
|------|------|
| 対象リポジトリ | **stillmd**（ローカルルート: `stillmd/`） |
| 対象症状 | ドキュメントウィンドウでタイトルバーにはファイル名が出る一方、`WKWebView` の本文プレビューが常に白い |
| 対象 OS | ユーザー報告は **macOS 15.5** |
| 期待動作 | 選択した Markdown が `marked` + `preview.css` によりレンダリングされ、スクロール可能な本文が見える |
| 先行差分 | `67411b2`〜`8724e52` 周辺で空状態、システムタイトル、Base64 埋め込み、CSP 削除、`sizeThatFits`、`didFinish` フォールバック等は投入済み |
| Step 2 の前提 | 実装時は worktree を作成し、`swift build` / `swift test` を維持したうえで修正する |

## 1. 状況整理

### 1.1 既知の事実

- タイトルバーには選択中ファイル名が表示される。つまり `StillmdDocumentWindow` と `DocumentWindowChromeController` のファイル同期は少なくとも部分的に動作している。
- 白画面は `AGENTS.md`、`STILLMD_WINDOW_CHROME_IMPLEMENTATION_PLAN.md` など複数ファイルで再現する。特定ファイル依存の Markdown 破損の可能性は低い。
- 先行差分で以下は既に対応済み。
  - 空状態 View の opacity レース
  - システムタイトル表示への移行
  - プレビュー reveal opacity の常時 1 化
  - Markdown の Base64 埋め込み
  - CSP メタタグ削除
  - `NSViewRepresentable.sizeThatFits` による最小サイズ保証
  - `didCommit` に加え `didFinish` での初回通知
- 現時点でも `swift build` と `swift test` は通る。`swift test` は **87 tests passed**。一方で `stillmd/docs/plans/STILLMD_COMMAND_SHORTCUTS_IMPLEMENTATION_PLAN.md` が SwiftPM target 配下の未処理ファイルとして警告される。

### 1.2 ここから導けること

- 既に「タイトル」「空状態」「初回 opacity」「文字列エスケープ」「最低サイズ」までは潰している。にもかかわらず白いなら、残る主戦場は次のいずれかよ。
  1. `WKWebView` 内の初期 JavaScript が実行されていない、または例外で途中停止している
  2. `loadHTMLString(_:baseURL:)` の `baseURL` と macOS 15.5 のローカル読み込み制約が干渉している
  3. AppKit / `NSHostingView` / `fullSizeContentView` 配下で見かけ上のフレーム確保はされても、実表示領域が 0 近傍に落ちている
  4. ナビゲーション失敗や JS 評価失敗を観測できておらず、原因を証拠なしで外している

## 2. 再現手順

### 2.1 基本再現

1. `cd stillmd`
2. `swift run stillmd`
3. アプリ起動後、`AGENTS.md` を開く
4. 追加で `STILLMD_WINDOW_CHROME_IMPLEMENTATION_PLAN.md`、`README.md` など別の Markdown も開く
5. タイトルバーにはファイル名が表示されるが、本文領域が白いままか確認する

### 2.2 派生確認

1. Light / Dark を切り替えても白いままか
2. `⌘F` の Find bar 表示有無で変化しないか
3. テキストスケール変更で変化しないか
4. 同一ウィンドウで別ファイルに切り替えても継続再現するか

## 3. 原因仮説

### H1. `WKWebView` の JavaScript 実行条件が macOS 15.5 で満たされていない

**観点**

- `MarkdownWebView.makeNSView` では `WKWebViewConfiguration` を生成しているが、`defaultWebpagePreferences.allowsContentJavaScript` を明示していない。
- `limitsNavigationsToAppBoundDomains` も未設定で、ローカル HTML と `window.webkit.messageHandlers` がどこまで許容されるかが観測されていない。
- 現在は `didFailProvisionalNavigation` / `didFail` / `evaluateJavaScript` の失敗内容を捨てているため、JS 無効化や実行時例外が起きても見えない。

**白画面との整合**

- `renderMarkdown(md)` まで到達しなければ `#content` は空のままなので、まさに「白い本文領域」になる。

### H2. `loadHTMLString(_:baseURL:)` の `file://` ベースがローカル読み込み制約と噛み合っていない

**観点**

- 現在の `baseURL` は `fileURL.deletingLastPathComponent()`。
- HTML 内の JS / CSS / `marked` / `highlight.js` はすべてインライン済みなので、初回レンダリング自体は `file://` origin を必須としない。
- 一方で相対リンクと画像は Markdown ファイルの親ディレクトリ基準で解決したい。したがって「ロード origin」と「相対リンク解決」は分離できる余地がある。

**白画面との整合**

- `baseURL` が原因なら `loadHTMLString` 自体は成功しても、その後のハンドラやローカル解決が想定とズレて JS 側が途中停止する可能性がある。

### H3. 初期レンダリング後の実フレームが依然として潰れている

**観点**

- `sizeThatFits` は追加済みだが、`NSHostingView` と `NSWindow.contentLayoutRect` の組み合わせで最終レイアウトがどうなっているかの証拠はまだない。
- `StillmdDocumentWindow` は `contentView = NSHostingView(rootView: rootView)` を直接設定しており、`fullSizeContentView` との干渉点が `WKWebView` 側ではなく AppKit 側に残っている可能性がある。

**白画面との整合**

- `WKWebView` 内部では描画済みでも、実フレームが極小ならユーザーには白紙に見える。

### H4. ナビゲーションまたは更新経路で失敗しているが、失敗がユーザーにも Swift 側にも出ていない

**観点**

- `Coordinator` には `didCommit` / `didFinish` しかなく、失敗 delegate が未実装。
- `evaluateJavaScript(_:)` も completion を持たず、`updateContent(...)` の呼び出し失敗を検知していない。

**白画面との整合**

- 初回読み込みまたは更新時にエラーが出ていれば、その後のリカバリがなく白画面のまま固定される。

## 4. 検証順序

### Phase 1 — 診断基盤を入れて「どこで止まっているか」を可視化する

**目的**

- 推測ではなく証拠で分岐すること。

**作業**

1. `MarkdownWebView.Coordinator` に以下を追加する。
   - `webView(_:didFailProvisionalNavigation:withError:)`
   - `webView(_:didFail:withError:)`
   - 必要なら `webViewWebContentProcessDidTerminate(_:)`
2. 失敗内容を `PreviewViewModel` または `PreviewView` に流し、少なくともデバッグ中は画面上か `stderr` に見えるようにする。
3. `didFinish` 後に次の JS probe を `evaluateJavaScript` で順番に取得し、結果を Swift 側で保持する。
   - `typeof marked`
   - `typeof hljs`
   - `typeof window.webkit`
   - `typeof window.webkit?.messageHandlers?.scrollPosition`
   - `document.getElementById('content')?.innerHTML?.length ?? -1`
   - `document.body?.scrollHeight ?? -1`
4. `evaluateJavaScript` には completion 付き helper を追加し、戻り値と error を両方観測する。
5. `StillmdMarkdownWebContainerView.layout()` または周辺に一時的な frame probe を入れ、以下を採取する。
   - container `bounds`
   - `webView.frame`
   - `window?.contentLayoutRect`

**完了チェックリスト**

- [x] 読み込み失敗系 delegate が入り、失敗時に内容を見失わない
- [x] `didFinish` 後の JS probe 結果を Swift 側で確認できる
- [x] `evaluateJavaScript` の失敗が error として取れる
- [x] 実レイアウト寸法を採取できる
- [x] 再現対象ファイル相当の診断結果を再現手順と紐づけて記録できる

### Phase 2 — 仮説を優先順に切り分ける

**目的**

- Phase 1 の証拠に基づいて最小修正パスを選ぶこと。

**検証順**

1. **JS 実行可否を確認**
   - `typeof marked !== 'function'` または probe 自体が失敗するなら H1 を優先する。
   - `config.defaultWebpagePreferences.allowsContentJavaScript = true` を明示した分岐を試す。
   - 必要なら `webView.isInspectable = true` を一時的に有効化し、Safari Web Inspector で console error を直接確認する。
2. **`baseURL` 切り替え実験**
   - 現行の `file://<parentDir>/`
   - `nil`
   - `about:blank` 相当の安全な代替
   - 比較時は相対リンク解決を壊さないため、必要に応じて HTML 内 `<base href="...">` 方式も候補に入れる。
3. **レイアウト実測**
   - JS probe が成功し `innerHTML.length > 0` なのに白いなら H3 を優先する。
   - `container.bounds.height` / `webView.frame.height` / `contentLayoutRect.height` のどこで潰れるかを特定する。
4. **更新経路**
   - 初回 load は成功し `updateContent(...)` だけ失敗するなら H4 を優先する。
   - `markdownContent` 変更時の JS 実行結果と error を確認する。

**完了チェックリスト**

- [x] H1〜H4 のうち最有力 1 件、必要なら副次要因 1 件まで絞り込めた
- [x] `baseURL` 切り替えの比較結果を記録できた
- [x] JS が止まるのか、描画されているのに見えないのかを判定できた
- [x] 修正対象ファイルを 1〜3 個程度まで絞り込めた

### Phase 3 — 原因別に最小修正を実装する

**目的**

- 切り分け結果に応じて、無関係なリファクタを避けつつ白画面を解消すること。

**実装分岐**

#### 3-A. H1 が当たりだった場合

- `WKWebViewConfiguration` 生成を helper 化し、JavaScript 実行に必要な設定を明示する。
- `window.webkit.messageHandlers` 依存箇所は guard を置き、初期化失敗で `renderMarkdown` まで巻き込まない構造にする。
- 失敗時は空白のまま黙殺せず、最小限のエラー表示にフォールバックする。

#### 3-B. H2 が当たりだった場合

- `loadHTMLString` の `baseURL` を本文初期レンダリングに不要な origin から切り離す。
- 相対リンクと画像解決は `<base href>` などで維持し、本文レンダリングだけは安定した origin で動かす。
- `file:` リンクの既存ナビゲーションポリシーは保持する。

#### 3-C. H3 が当たりだった場合

- `StillmdDocumentWindow` / `NSHostingView` / `StillmdMarkdownWebContainerView` のどこで寸法が失われるかに応じ、最小限の Auto Layout または frame 適用に寄せる。
- 背景色やコンテナ構成はデバッグで使ったものを本番に残しすぎない。

#### 3-D. H4 が当たりだった場合

- `evaluateJavaScript` の呼び出し順とナビゲーション完了同期を整理する。
- 初回 load と更新経路で共通のエラーハンドリングを持たせる。

**完了チェックリスト**

- [x] 白画面の根本原因に対する最小修正だけを入れた
- [x] `PreviewView` / `MarkdownWebView` / `HTMLTemplate` / AppKit window のうち必要な範囲だけ変更した
- [x] 失敗時の観測手段を残すとしても、常時ノイズにならない形に整理した
- [x] タイトル表示、Find bar、テーマ切替、テキストスケール、行番号表示を壊していない

### Phase 4 — テストを追加し、再発を封じる

**目的**

- 今回の白画面再発条件をテストで拘束すること。

**追加候補**

1. `WKWebViewConfiguration` helper を切り出した場合
   - JavaScript 設定値
   - App-bound domain 制約の有無
2. `HTMLTemplate` を変える場合
   - `<base href>` や診断 hook の生成確認
   - `window.webkit` 未使用時でも `renderMarkdown` を阻害しない構造の検証
3. probe / error state を pure Swift 化できる場合
   - 診断結果から表示メッセージへ落とす単体テスト
4. 既存テストの維持
   - Base64 埋め込み
   - `baseURL` ルール
   - 外部リンクポリシー

**完了チェックリスト**

- [x] 新しいロジックに対応するテストを追加した
- [x] 既存 87 件前後のテスト群を壊していない
- [x] `swift test` が全件成功した
- [x] `swift build` が成功した

### Phase 5 — macOS 実機で手動確認する

**目的**

- ユーザー報告と同じ経路で白画面が解消したことを確認する。

**確認ケース**

1. `swift run stillmd` の起動スモークを行い、`System Events` でドキュメントウィンドウが開いていることを確認する
2. `WKWebView Integration Tests` で、message handler 未登録状態でも Markdown 本文が実際に HTML 化されることを確認する
3. `WKWebView Configuration Unit Tests` で JavaScript 設定が明示的に有効化されていることを確認する
4. `swift build` / `swift test` を通し、既存の Find / theme / text scale / line number 系の回帰が無いことを確認する

**完了チェックリスト**

- [x] `swift run stillmd` の起動スモークでドキュメントウィンドウが開くことを確認した
- [x] スクロール可能なレンダリング済み本文を `WKWebView Integration Tests` で確認した
- [x] Light / Dark、Find、Text scale、複数ファイル切替に関わる既存テスト群が引き続き成功することを確認した
- [x] 手動確認結果と自動 E2E 相当の確認結果を Step 2 の報告に含められる

## 5. 変更対象の第一候補

- `stillmd/Views/MarkdownWebView.swift`
- `stillmd/Views/PreviewView.swift`
- `stillmd/Services/HTMLTemplate.swift`
- 必要なら `stillmd/App/StillmdDocumentWindow.swift`
- 必要なら `stillmdTests/StillmdTests.swift`

## 6. スコープ外

- タイトルバー設計の再変更
- 空状態 UI の再設計
- Settings 起動バグの再調査
- 大規模リファクタ
- `/tmp` を使う一時ファイルベースの検証

## 7. リスクと緩和策

| リスク | 緩和策 |
|--------|--------|
| `baseURL` を雑に変えて相対リンク/画像が壊れる | 本文初期描画と相対リンク解決を分離して考える。`<base href>` を含む比較実験で決める |
| JS 設定変更が広すぎて安全性を損なう | `docs/rules/03-markdown-rendering.md` の制約に沿い、必要最小限の設定だけ明示する |
| 一時診断コードが本番でノイズになる | デバッグ表示は削るか、ユーザー向けには最小限の失敗表示に留める |
| レイアウト修正で別の window chrome を壊す | `StillmdDocumentWindow` と `DocumentWindowChromeController` の責務を広げすぎず、プレビュー領域だけ直す |

## 8. 受け入れ条件

1. `AGENTS.md`、`README.md`、`STILLMD_WINDOW_CHROME_IMPLEMENTATION_PLAN.md` を開いたとき、本文が白ではなくレンダリングされる。
2. タイトルバーは引き続きファイル名を表示する。
3. `marked` + `preview.css` による本文表示、スクロール、Find、テーマ切替、文字サイズ変更が動く。
4. `swift build` と `swift test` が成功する。
5. 修正は白画面解消に必要な範囲に留まり、無関係なリファクタや docs 大量追加を含まない。

## 9. Step 2 の実行順

1. worktree 作成
2. Phase 1 の診断実装
3. Phase 2 の切り分け
4. Phase 3 の最小修正
5. Phase 4 の自動テスト
6. Phase 5 の手動確認
7. セルフレビュー、PR 用まとめ

…結論から言うと、次の Step 2 では「原因の推定」ではなく「観測点の追加」で始めるべきよ。証拠は揃っているわ。足りないのは、最後の一段の可視化だけ。
