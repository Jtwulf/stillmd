# stillmd テーマモードの System 廃止 / Light・Dark 2値化 実装計画書

## 0. メタ情報

| 項目 | 内容 |
|------|------|
| 対象リポジトリ | **stillmd**（ローカルルート: `stillmd/`） |
| 目的 | テーマモードを `System / Light / Dark` の 3 値から `Light / Dark` の 2 値へ縮小する |
| 背景 | `System` は複数層で `prefers-color-scheme` 依存を発生させ、挙動のばらつきと不具合源になっている |
| 方針 | 新規の `System` 選択を廃止し、既存の保存値は安全に明示テーマへ正規化する |
| Step 2 の前提 | 実装時は worktree を作成し、`swift build` / `swift test` を維持したうえで修正する |

## 1. 要件整理

ユーザー意図を整理すると、今回ほしいのは次の 3 点。

1. テーマ選択を `Light / Dark` のみにしたい
2. `System` に起因する不安定さをなくしたい
3. それに伴って不要になる分岐やコードをきれいに削りたい

### 守ること

- preview-only / ミニマル / 静けさ / 軽量性を壊さない
- Settings の項目を増やさない
- 既存ユーザーの保存値が壊れないようにする
- `Light / Dark` の切り替えは即時反映を維持する
- window chrome / preview / WebView の見え方がずれない

### 追加の判断

- 既存の `themePreference = "system"` は、更新後にそのまま残さず、初回読み込み時に `light` か `dark` へ正規化する
- 正規化先は、可能ならその時点の明示的な外観を採用する
- 取得できない場合の安全策は `light`

…つまり、`System` を UI から消すだけでは足りない。保存値と実行時分岐も同時に片付ける必要がある。

---

## 2. Step 1 時点のキャッチアップ結果

### 2.1 主要な関連ファイル

- `stillmd/Services/AppPreferences.swift`
  - `ThemePreference` が `system / light / dark` の 3 値
  - `colorScheme` が `ThemePreference.system` のとき `nil`
- `stillmd/App/StillmdApp.swift`
  - `@AppStorage` の既定値が `ThemePreference.system.rawValue`
  - `Settings` 画面に `preferredColorScheme(themePreference.colorScheme)` を適用
- `stillmd/Views/RootView.swift`
  - `ThemePreference.system` を前提に `resolvedColorScheme` を算出
  - `preferredColorScheme(themePreference.colorScheme)` と `colorScheme` 監視がある
- `stillmd/Views/SettingsView.swift`
  - `Picker` が `ThemePreference.allCases` を列挙している
- `stillmd/Views/PreviewView.swift`
  - `@AppStorage` の既定値が `ThemePreference.system.rawValue`
  - `MarkdownWebView` に `themePreference.rawValue` を渡している
- `stillmd/Views/MarkdownWebView.swift`
  - HTML と JS のテーマ切替が `system` 分岐を含む
  - `setThemePreference` と `updateTheme` が `prefers-color-scheme` へ依存
- `stillmd/Services/HTMLTemplate.swift`
  - `viewerState.themePreference === 'system'` の分岐がある
  - `window.matchMedia('(prefers-color-scheme: dark)')` を監視している
- `stillmd/App/DocumentWindowChromeController.swift`
  - 新規ウィンドウの初期色を `system` 前提で解決している
- `stillmdTests/StillmdTests.swift`
  - `ThemePreference.system` の nil 設定を前提にしたテストがある
  - HTML 文字列に `setThemePreference` / `data-theme-preference` があることを見ている

### 2.2 ここから導けること

- `system` は UI 表示だけの話ではない
- SwiftUI の設定画面、AppStorage の既定値、WebView の JS、Window chrome 初期化まで食い込んでいる
- したがって、変更は「列挙値を 1 個消す」だけでは終わらない

---

## 3. 実装方針

### 方針 A: 公開テーマは `Light / Dark` のみ

- `ThemePreference` は 2 ケースにする
- `CaseIterable` は維持するが、`allCases` は `light / dark` のみになる
- `SettingsView` の選択肢も `Light / Dark` のみ
- `Mode` 切替 UI が他にあれば同様に `System` を消す

### 方針 B: 新規の `system` 依存を完全に止める

- `preferredColorScheme(nil)` に相当する処理をなくす
- `window.matchMedia('(prefers-color-scheme: dark)')` の監視を削除する
- `system` による `themePreference` 再解釈を削除する
- JS 側の `default` / `dark` 2値化に寄せる

### 方針 C: 既存保存値は安全に移行する

- `ThemePreference(rawValue:)` で `system` または不正値を読んだら、即座に明示テーマへ正規化する
- 可能なら現在の見え方に近い `light` / `dark` を採用する
- その後の保存先は 2 値のみとする

### 方針 D: 不要コードはまとめて削る

- `nil` 返却型の `colorScheme` をやめる
- `resolvedColorScheme` のような System 向け補助を減らす
- `mediaQuery` 依存の更新処理を消す
- `system` を含むテストを整理する

---

## 4. Phase 設計

## Phase 1: 影響範囲と移行ルールを固定する

目的: `system` をどこで受け、どこで捨てるかを先に決める。

- [ ] `ThemePreference` の最終形を `light / dark` の 2 値に固定する
- [ ] 旧保存値 `system` の移行先を決める
- [ ] `AppStorage` の既定値を `light` に寄せるか、起動時解決に寄せるかを決める
- [ ] `SettingsView` / `RootView` / `PreviewView` / `MarkdownWebView` / `HTMLTemplate` / `DocumentWindowChromeController` の修正点を洗い出す
- [ ] 既存テストのどれを削除し、どれを更新するかを整理する
- [ ] この計画書の完了条件に、`system` 参照がなくなることを明記する

### Phase 1 完了条件

- [ ] `system` を残すのが必要な場所と不要な場所が分離できている
- [ ] 旧データ移行の扱いが曖昧ではない
- [ ] 変更対象ファイルの一覧が確定している

## Phase 2: テーマ列挙と UI を 2 値化する

目的: ユーザーが選べるテーマを `Light / Dark` だけにする。

- [ ] `ThemePreference` から `system` を削除する
- [ ] `displayName` を 2 値に整理する
- [ ] `colorScheme` を `ColorScheme` 非 optional に変更する
- [ ] `SettingsView` の Picker から `System` を消す
- [ ] `StillmdApp` の Settings 初期値を 2 値前提にする
- [ ] `PreviewView` の `@AppStorage` 初期値を 2 値前提にする
- [ ] `RootView` の `resolvedColorScheme` を簡略化する
- [ ] `ThemePreference.allCases` を前提にしている表示を確認する
- [ ] 画面上の文言が `Light / Dark` のみになっていることを確認する

### Phase 2 完了条件

- [ ] どの画面でも `System` を選べない
- [ ] 既定値が `light` 側に収束している
- [ ] コンパイル上の `system` 依存が UI から消えている

## Phase 3: runtime と WebView の System 分岐を削る

目的: `prefers-color-scheme` への追従をやめ、明示テーマだけで動かす。

- [ ] `HTMLTemplate.build` の既定 theme 引数を 2 値前提にする
- [ ] `viewerState.themePreference === 'system'` 分岐を削除する
- [ ] `applyTheme()` を `light / dark` だけで完結させる
- [ ] `setThemePreference()` の fallback を `system` ではなく明示テーマにする
- [ ] `window.matchMedia('(prefers-color-scheme: dark)')` とその listener を削除する
- [ ] Mermaid の theme 解決を 2 値前提に整理する
- [ ] `MarkdownWebView` の `Coordinator` が `system` を保持しないようにする
- [ ] `DocumentWindowChromeBootstrap` の初期色解決を 2 値前提に整理する
- [ ] `RootView` の `colorScheme` 監視が不要なら削除する

### Phase 3 完了条件

- [ ] `System` による runtime 分岐が HTML / JS / Swift のどこにも残っていない
- [ ] テーマ変更時の挙動が `Light / Dark` の切替だけで説明できる
- [ ] 画面再描画やウィンドウ chrome の同期に余計な依存が残っていない

## Phase 4: 旧値正規化と不要コードの後始末をする

目的: 既存ユーザーの保存値を壊さず、不要な枝を残さない。

- [ ] `ThemePreference(rawValue:)` が `system` を読んだときの正規化を入れる
- [ ] 正規化結果を AppStorage に書き戻す必要があるか確認する
- [ ] `system` を前提にしたフォールバックコードを削る
- [ ] `ThemePreference.system.colorScheme == nil` のような旧テストを削除または置換する
- [ ] `ThemePreference` の `allCases` テストを 2 値前提に更新する
- [ ] HTML 文字列のテストを新ロジックに合わせて更新する
- [ ] `system` 文字列が残るのが意図的な箇所だけか再確認する
- [ ] 不要になったコメントや補助メソッドを削除する

### Phase 4 完了条件

- [ ] 旧 `system` 保存値が残っても壊れない
- [ ] ただし新規保存値は `light / dark` のみになる
- [ ] `system` 由来の dead code が整理されている

## Phase 5: テスト・検証・回帰確認を行う

目的: 仕様変更が UI と runtime の両方で成立していることを確認する。

### 自動テスト

- [ ] `swift build`
- [ ] `swift test`
- [ ] `ThemePreference` の 2 値化テスト
- [ ] 旧 `system` 値の正規化テスト
- [ ] Settings / HTMLTemplate / WebView 文字列の回帰テスト

### 手動確認

- [ ] Settings で `Light / Dark` のみが出る
- [ ] `Light` に切り替えたあと再起動して保持される
- [ ] `Dark` に切り替えたあと再起動して保持される
- [ ] 旧 `system` 保存状態から起動しても破綻しない
- [ ] Preview の背景、本文、コードブロック、ウィンドウ chrome が両テーマで破綻しない
- [ ] `System` を示す文言やトグルが UI に残っていない

### Phase 5 完了条件

- [ ] ビルドとテストが通る
- [ ] 目視で light / dark の両方に問題がない
- [ ] `System` の入口と依存が消えている

---

## 5. 対象ファイル候補

- `stillmd/Services/AppPreferences.swift`
- `stillmd/App/StillmdApp.swift`
- `stillmd/Views/RootView.swift`
- `stillmd/Views/SettingsView.swift`
- `stillmd/Views/PreviewView.swift`
- `stillmd/Views/MarkdownWebView.swift`
- `stillmd/Services/HTMLTemplate.swift`
- `stillmd/App/DocumentWindowChromeController.swift`
- `stillmdTests/StillmdTests.swift`

## 6. Step 2 への引き継ぎ

- まず `ThemePreference` の 2 値化と旧値移行方針を実装する
- 次に UI と runtime の `system` 分岐をまとめて除去する
- 最後にテストを更新し、`swift build` / `swift test` と手動確認で閉じる

