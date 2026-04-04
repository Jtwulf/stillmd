# stillmd: 基本コマンド操作 / 行番号 / 表示倍率 実装計画書

## 位置づけ

- 対象リポジトリ: `stillmd`
- 対象機能:
  - `⌘N` で新規ウインドウ
  - `⌘B` でファイル全体の行番号表示を表示・非表示
  - コードブロックの行番号はデフォルト表示
  - `⌘F` で検索バーの表示・非表示をトグル
  - `⌘+` / `⌘-` / `⌘0` で表示倍率の拡大・縮小・リセット
- 関連既存実装:
  - `stillmd/App/StillmdApp.swift`
  - `stillmd/App/FindCommands.swift`
  - `stillmd/Views/RootView.swift`
  - `stillmd/Views/PreviewView.swift`
  - `stillmd/Views/MarkdownWebView.swift`
  - `stillmd/Views/SettingsView.swift`
  - `stillmd/Services/AppPreferences.swift`
  - `stillmd/Services/HTMLTemplate.swift`
  - `stillmd/Resources/preview.css`
  - `stillmdTests/StillmdTests.swift`

## 前提・現状整理（Step 1 時点）

### 1. `⌘N`

- `StillmdApp.swift` は `CommandGroup(replacing: .newItem)` で標準 `New` を消し、`Open…` に置き換えている。
- そのため現状の app menu には `⌘N` に相当する新規ウインドウ導線がない。
- 一方で `RootView` は `fileURL == nil` の空ウインドウを扱えるため、空ウインドウモデル自体は既存設計に存在する。

### 2. `⌘F`

- `FindCommands.swift` の `Find…` は常に `showFindBarAction?.perform()` を呼ぶ。
- `PreviewView.swift` の `presentFindBar()` は表示専用で、表示中に再度 `⌘F` を押しても閉じない。
- `Esc` では閉じられるため、現状の問題は **`⌘F` が toggle でない**点にある。

### 3. `⌘B` と行番号

- 行番号表示は現状未実装。
- ユーザー要件は「コードブロック限定」ではなく、**ファイル全体の行番号**。
- ただしコードブロックの行番号は別途「デフォルトで表示」にしたい、という要求が追加されている。

### 4. 表示倍率ショートカット

- `SettingsView.swift` と `AppPreferences.swift` に `Text Scale` の設定が存在する。
- つまり表示倍率の状態管理そのものは既存実装があり、ショートカット導線の追加余地がある。
- `⌘,` は `Settings` scene があるので macOS 標準導線で足りる前提とする。

## 要件整理

### 必須要件

1. `⌘N` で空の新規ウインドウを開けること
2. `⌘B` で **ファイル全体の行番号表示**を表示・非表示できること
3. コードブロックには **デフォルトで行番号が出ている**こと
4. `⌘F` で検索バーが表示中なら閉じ、非表示なら開くこと
5. `⌘+` / `⌘-` / `⌘0` で表示倍率を変更できること

### 守ること

- preview-only の境界を壊さない
- 常設ツールバーや本文より目立つ補助 UI を増やさない
- 行番号は補助表示であり、本文可読性を壊さない
- `⌘F`, `⌘G`, `⇧⌘G`, `Esc`, `⌘O`, 複数ウインドウ, Finder 連携を壊さない
- `Text Scale` の既存設定と矛盾しない
- `swift build` / `swift test` を通す

### 今回の設計前提

- **本文全体の行番号**と**コードブロックの行番号**は別物として扱う
- `⌘B` は本文全体の行番号レイヤを切り替える
- コードブロックの行番号は `⌘B` に依存させず、デフォルト表示を基本とする
- 本文全体の行番号状態は window-local の一時 state とし、まずは永続化しない
- コードブロックの行番号デフォルト表示も Settings 項目には増やさない
- `⌘B` は Bold 系ショートカットとの競合感がないか Step 2 の実機確認対象に含める

## 実装方針

### A. コマンド責務の整理

- `StillmdApp.swift` で app-wide command と focused command を整理する
- `⌘N`, `⌘O`, `⌘+`, `⌘-`, `⌘0` は app-wide command として扱う
- `⌘F`, `⌘B` は focused scene に委譲する
- `FindCommands.swift` は Find 専用のまま活かしつつ、toggle 対応へ拡張する
- 行番号表示も FocusedValue 経由で `PreviewView` の state を操作する

### B. `⌘N` の方針

- `Open…` と `New Window` を共存させる
- `WindowGroup` ベースの既存 URL ウインドウ管理を壊さず、空 state の新規 scene を開く導線を追加する
- 完了条件は「`⌘N` で空ウインドウが開き、その空ウインドウから `⌘O` でファイルを開ける」こと

### C. `⌘F` toggle の方針

- `showFindBarAction` を単なる表示専用ではなく toggle に寄せる
- `PreviewView` に `toggleFindBar()` を追加し、`⌘F`, close button, `Esc` の閉じる経路を揃える
- `⌘G` / `⇧⌘G` は現状どおり未表示時に検索バーを出してから next / previous を実行できるよう維持する

### D. ファイル全体の行番号表示の方針

- SwiftUI 側に **本文全体の行番号表示 state** を持つ
- `MarkdownWebView` と `HTMLTemplate` の連携で、preview 全体の各 block 要素に対し縦方向の行番号レイヤを与える
- 表示対象は見出し・段落・リスト・引用・コードブロック・表などを含む「最終レンダリング後の表示行」とし、Step 2 で DOM 構造と描画コストを見ながら実装方式を確定する
- ここは不確定要素があるため、Phase 1 で小さくスパイクし、以下のどちらを採るか判断する
  1. CSS counter と block 単位レイアウトで近似する
  2. JS でレンダリング後 DOM から行番号レイヤを構築する
- 要件上は **ファイル全体に対して一貫した行番号列が見えること** を優先し、内部方式は Step 2 で最終判断する

### E. コードブロック行番号のデフォルト表示方針

- fenced code block には常時行番号を付ける
- これは本文全体の行番号表示とは独立した責務とする
- `HTMLTemplate.swift` で code block に対する line-number decorator を入れ、`preview.css` で gutter を静かに見せる
- code block の水平スクロール、syntax highlight、検索ハイライト、選択感を壊さないことを優先する

### F. 表示倍率ショートカットの方針

- `AppPreferences.textScale` の既存 state をそのまま使う
- `⌘+` と `⌘-` は範囲内で 1 step ずつ増減
- `⌘0` は `AppPreferences.defaultTextScale` に戻す
- Settings の slider とショートカットが同じ state を共有し、即時反映されることを完了条件にする

## 技術的論点

### 1. ファイル全体の行番号は実装難度が高い

…ここが最大の論点よ。

- Markdown は段落やリストで折り返され、表示行は固定ではない
- WKWebView の最終描画結果に対して一貫した「行番号」を出すには、DOM / CSS / JS の協調が必要
- したがって Step 2 では、**まず UI と性能が成立する最小方式を先に決める**必要がある

結論から言うと、現時点では「Markdown source の論理行番号」と「画面表示行番号」は一致しない可能性が高い。  
今回の要件は後者、つまり **プレビュー上で見えるファイル全体の行番号列** と解釈して計画を組む。

### 2. 本文全体の行番号とコードブロック行番号の二重表示

- `⌘B` を ON にした状態でコードブロックにも独自行番号があるため、視覚的な二重化が起こりうる
- Step 2 では次のどちらかを選ぶ
  1. code block 内でも二層のまま見せる
  2. 本文全体の行番号 ON 中は code block 独自 gutter の見せ方を少し抑える
- どちらにせよ、**ユーザーが今どの行を見ているかが分かること**を優先する

### 3. `⌘+` のキーバリエーション

- macOS では `⌘=` が実質 `⌘+` として扱われるケースがある
- Step 2 では実機で `⌘=` / `⇧⌘=` の扱いも確認し、必要ならメニュー表記との整合を取る

### 4. `⌘N` と `⌘O` の両立

- `.newItem` を雑に戻すと `Open…` 導線を失う可能性がある
- したがって File menu 全体を再整理し、順序とショートカットの整合まで確認する

## Phase 分割とチェックリスト

### Phase 1: コマンド基盤と技術スパイク

- [ ] `StillmdApp.swift` の command 構成を棚卸しし、`⌘N`, `⌘O`, `⌘F`, `⌘B`, `⌘+`, `⌘-`, `⌘0` の責務を整理する
- [ ] `FindCommands.swift` に toggle 用 FocusedValue を追加する設計を確定する
- [ ] 行番号表示用 FocusedValue を追加する設計を確定する
- [ ] 本文全体の行番号について、CSS counter ベースか JS レイヤベースかを小さく検証する
- [ ] code block 行番号 decorator の最小方式を決める
- [ ] preview 不在時に `⌘F` / `⌘B` が誤作動しない条件を整理する
- [ ] `swift build` が通る
- [ ] `swift test` が通る

### Phase 2: `⌘N` 新規ウインドウ

- [ ] `⌘N` で空ウインドウを開ける実装を追加する
- [ ] `⌘O` は維持し、File menu から引き続き `Open…` を呼べる
- [ ] 空ウインドウから `⌘O` でファイルを開ける
- [ ] 既存ファイルウインドウがある状態でも `⌘N` で追加の空ウインドウを開ける
- [ ] Finder / Dock / `windowManager.openFile(_:)` 経由の URL ベースフローを壊さない
- [ ] `swift build` / `swift test` が通る

### Phase 3: `⌘F` toggle 化

- [ ] `⌘F` 押下で検索バーが未表示なら表示される
- [ ] `⌘F` 押下で検索バーが表示中なら閉じる
- [ ] close button と `Esc` と `⌘F` の閉じる経路が同じ状態遷移に揃う
- [ ] 非表示後に検索クエリとハイライトが残留しない
- [ ] `⌘G` / `⇧⌘G` が引き続き機能する
- [ ] `swift build` / `swift test` が通る

### Phase 4: コードブロック行番号のデフォルト表示

- [ ] fenced code block に常時行番号が出る
- [ ] syntax highlight と行番号が両立する
- [ ] 横スクロールと選択感が破綻しない
- [ ] 検索ハイライトが code block 内でも破綻しない
- [ ] light / dark の両方で gutter が本文より目立ちすぎない
- [ ] `swift build` / `swift test` が通る

### Phase 5: `⌘B` によるファイル全体の行番号表示

- [ ] `⌘B` 押下でファイル全体の行番号列が表示される
- [ ] `⌘B` 再押下で非表示に戻る
- [ ] 見出し・段落・リスト・引用・表・コードブロックを含む長文で一貫した行番号表示になる
- [ ] 本文可読性を著しく落とさない
- [ ] code block 行番号との併用時に視認性が破綻しない
- [ ] テーマ切替、表示倍率変更、再読み込み後も状態が破綻しない
- [ ] `swift build` / `swift test` が通る

### Phase 6: 表示倍率ショートカット

- [ ] `⌘+` / `⌘=` 系入力で表示倍率が増える
- [ ] `⌘-` で表示倍率が減る
- [ ] `⌘0` で 100% に戻る
- [ ] Settings の slider とショートカットが同じ state を共有する
- [ ] clamped range (`0.85...1.30`) を超えない
- [ ] `swift build` / `swift test` が通る

### Phase 7: 回帰確認

- [ ] `⌘N` → 空ウインドウ → `⌘O` の導線が通る
- [ ] 同じファイルを複数回開いたときの duplicate detection が維持される
- [ ] `⌘F`, `⌘G`, `⇧⌘G`, `Esc` の連携が崩れない
- [ ] `⌘B` の ON/OFF でスクロール位置や描画が大きく崩れない
- [ ] 長い Markdown / 長いコードブロックで体感性能が著しく悪化しない
- [ ] `swift build`
- [ ] `swift test`
- [ ] 実機で light / dark を目視確認

## テスト計画

### 自動テスト

- 既存 `stillmdTests/StillmdTests.swift` に次の回帰防止を追加する
  - `HTMLTemplate` に検索 toggle 実装で必要な関数・state が含まれること
  - `HTMLTemplate` に code block 行番号用の JS / DOM フックが含まれること
  - `HTMLTemplate` に本文全体の行番号表示用フックが含まれること
  - 表示倍率ショートカットで使う state 更新ロジックを unit-test 可能に切り出せるならテストすること
- 既存 `WindowManager`・`HTMLTemplate`・`AppPreferences` テストがすべて通ること

### 手動確認

- `⌘N` で 2 枚以上の空ウインドウを開ける
- 空ウインドウ・ファイル表示ウインドウの両方で `⌘O` が機能する
- preview 中に `⌘F` を 2 回押して表示・非表示が往復する
- `⌘G` / `⇧⌘G` が機能する
- `⌘B` を 2 回押して本文全体の行番号表示が往復する
- code block はデフォルトで行番号が出る
- `⌘B` ON 中でも code block 行番号が破綻しない
- `⌘+` / `⌘-` / `⌘0` が即時反映される
- 自動リロード後もショートカット状態が破綻しない

## 補足メモ

- `⌘,` は既存 `Settings` scene で足りる前提なので、今回の実装対象から外す
- 本文全体の行番号は要件上必要だが、実装方式によっては Step 2 中に性能・視認性トレードオフが出る可能性がある  
  その場合も「要件を満たす最小の静かな見せ方」を優先する

## 完了条件

- 上記 Phase 1〜7 のチェックリストがすべて `[x]`
- `⌘N`, `⌘B`, `⌘F`, `⌘+`, `⌘-`, `⌘0` が要件どおりに機能する
- code block 行番号がデフォルトで表示される
- 既存の preview-only 体験と複数ウインドウ挙動にデグレがない
- `swift build` / `swift test` が通る
