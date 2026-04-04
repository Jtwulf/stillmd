# stillmd ウインドウクロム一体化 実装計画書

## 概要

stillmd の現状 UI は、本文プレビュー面とウインドウ上部のクロムが別の層として見えやすい。
今回の目的は、macOS のウインドウコントロールボタンを iTerm のように本文側と一体化して見せ、stillmd の `preview-only / ミニマル / 静けさ` を崩さずに、より静かな読書面へ整えることにある。

今回の Step 2 では、以下を実装対象とする。

- ウインドウコントロールボタン領域とアプリ内容の背景を一体化する
- タイトルは `ファイル名のみ` を残す
- 可能ならファイルアイコン（proxy icon）を非表示にする
- Empty state / Markdown preview / Find bar 表示時を含む全画面で統一する
- Find bar の背景色をプレビュー背景と揃え、浮遊カード感を抑える

---

## 1. キャッチアップ結果

### 1.1 現状の構造

- [`stillmd/Views/PreviewView.swift`](../../stillmd/Views/PreviewView.swift) では、本文 `corePreview` に対して `safeAreaInset(edge: .top)` で `topChrome` を差し込んでいる
- そのため、検索バーやエラー帯は本文と別レイヤーの上部クロムとして見えやすい
- [`stillmd/Views/FindBar.swift`](../../stillmd/Views/FindBar.swift) の検索 UI は `RoundedRectangle + windowBackgroundColor + stroke` で独立したカードとして描かれている
- [`stillmd/Views/WindowAccessor.swift`](../../stillmd/Views/WindowAccessor.swift) は各ウインドウへ `representedURL` を設定している
- [`stillmd/Services/WindowManager.swift`](../../stillmd/Services/WindowManager.swift) の duplicate detection 後の `bringToFront` は `window.representedURL == url` に依存している
- [`stillmd/App/StillmdApp.swift`](../../stillmd/App/StillmdApp.swift) では、現時点で titlebar / full-size content view を統合する明示設定はない

### 1.2 現状から推定できること

- 今の「プレビュー領域」と「コントロールボタン領域」の分離感は、主に `safeAreaInset` による上部クロムの別扱いと、Window レベルの titlebar 統合不足の組み合わせで生じている可能性が高い
- `representedURL` は Finder 連携や proxy icon に関わる AppKit 標準挙動を有効にするため、ファイルアイコン表示の有力な原因候補である
- したがって、ファイル名だけを残してアイコンを消したい場合は、`representedURL` 依存の再設計が必要になる可能性がある

### 1.3 既存思想との整合

- `DESIGN.md` と `docs/rules/02-ui-implementation.md` は「本文より強いヘッダー / ツールバー」を避ける立場で一貫している
- したがって、今回の一体化は stillmd の思想に反しない。むしろ「分離して見える上部クロム」を静かに後退させる方向として整合的
- ただし、iTerm 風の見た目を目指しても、本文の可読性やドラッグ領域を犠牲にしてはならない

---

## 2. 要件整理

### 2.1 主要要件

- プレビュー面とウインドウコントロールボタン領域を視覚的に一体化する
- 一体化の対象は `Empty state` / `Markdown preview` / `Find bar 表示中` を含む全画面とする
- タイトルはファイル名のみを残す
- 可能であればファイルアイコンを消す
- Find bar の背景色はプレビュー背景と統一し、同じ面の上に載っているように見せる

### 2.2 明示的に守ること

- 本文開始位置はウインドウボタンと干渉しないこと
- 本文が主役であり続けること
- 検索 UI を常設ツールバー化しないこと
- 空状態でも不自然な別レイヤー感を出さないこと
- 既存の multi-window / duplicate detection / Finder 連携を壊さないこと

### 2.3 今回の解釈

- 「一体化」は、本文そのものを完全に titlebar 下へ侵食させることではなく、まず `背景面とクロムの分離感をなくす` ことを意味する
- 本文テキストや Empty state コンテンツは、traffic light と重ならない安全な余白を維持する
- タイトルの残し方は「ファイル名のみ」。ディレクトリ名や proxy icon メニューは優先度を下げる

---

## 3. 技術方針

### 3.1 Window レベルの統合

最優先は `NSWindow` 側で titlebar と content を分離しすぎない設定へ寄せること。

想定方針:

- `styleMask(.fullSizeContentView)` 相当の設定を適用し、コンテンツ背景が titlebar 背景まで自然に伸びる構成を検討する
- `titlebarAppearsTransparent` 相当の設定で、従来の別バー感を抑える
- タイトル表示は `visible` を維持しつつ、配置と余白が stillmd の静けさを壊さないよう調整する
- 必要なら Scene / View とは分離した `WindowChromeConfigurator` 的な責務を導入し、AppKit 設定を局所化する

### 3.2 コンテンツ側の統合

Window レベルの統合だけでは足りないため、SwiftUI 側でも上部クロムを「別帯」ではなく「同じ面の上の補助 UI」として再構成する。

想定方針:

- `PreviewView` の `safeAreaInset` 起点の構造を見直し、上部 UI が別の帯として見えにくいレイアウトへ寄せる
- 検索バー表示時も、背景面は本文と同一トーンで連続させる
- エラー帯が存在する場合も、同様に「別バー」へ戻らないよう整理する
- Empty state でも上端背景が titlebar と連続して見えるよう、Root レベルの背景責務を確認する

### 3.3 タイトルとファイルアイコンの扱い

ファイル名だけを残し、アイコンを抑制したい場合は `representedURL` の扱いが鍵になる。

想定方針:

- 第一候補: `representedURL` を外し、タイトルは明示的にファイル名文字列として設定する
- その場合、`WindowManager.bringToFront` が `representedURL` に依存しているため、別の window lookup 手段を導入する
- 候補としては、`WindowAccessor` 経由で `URL -> NSWindow` の参照を registry 化する方法が最も自然
- この変更により proxy icon が消える可能性が高いが、Finder のタイトルバー経由ナビゲーションは失われる可能性がある
- その trade-off は stillmd の「静けさ」優先と整合するかを Step 2 で最終確認する

### 3.4 Find bar の見た目

- `windowBackgroundColor` ベースの独立カード表現はやめ、プレビュー背景と同系の面へ寄せる
- 輪郭線・角丸・padding は必要最小限にとどめる
- 検索バーの存在は分かるが、ツールバーやフローティングパネルには見えないことを目標にする

---

## 4. 影響範囲

### 4.1 主変更候補

- `stillmd/App/StillmdApp.swift`
- `stillmd/Views/RootView.swift`
- `stillmd/Views/PreviewView.swift`
- `stillmd/Views/FindBar.swift`
- `stillmd/Views/WindowAccessor.swift`
- `stillmd/Services/WindowManager.swift`

### 4.2 追加の可能性があるファイル

- `stillmd/Views/EmptyStateView.swift`
- `stillmd/Views/ErrorView.swift`
- 新規: `stillmd/Services/WindowChromeConfigurator.swift` または同等の helper
- `stillmdTests/StillmdTests.swift`

---

## 5. Phase 分割とチェックリスト

### Phase 1: ウインドウクロムの責務整理

目的: titlebar と content の一体化に必要な責務を Window レベルへ分離し、変更点を明確にする

- [x] `NSWindow` の titlebar / full-size content 関連設定をどこで適用するのが自然か整理する
- [x] `WindowAccessor` を単なる `representedURL` 設定器ではなく、window 参照取得・設定の入口として再設計する方針を固める
- [x] `WindowManager.bringToFront` の `representedURL` 依存を代替できる構造を決める
- [x] Empty state と Markdown preview の両方に同じ window 設定が適用されることを確認する
- [x] ファイル名タイトルの設定責務を Window レベルで扱うか View レベルで扱うか決める

#### Phase 1 完了条件

- [x] titlebar 一体化の設定箇所が明確
- [x] proxy icon 抑制のための依存解消方針が明確
- [x] multi-window / duplicate detection への影響が説明できる

### Phase 2: 全画面での一体化レイアウト実装

目的: Empty state / Preview / Find 表示時を通じて、上部クロムと内容面を同一レイヤーとして見せる

- [x] titlebar 背景がコンテンツ面と分断して見えない設定を導入する
- [x] Empty state 上端が titlebar と連続して見えることを確認する
- [x] Markdown preview 上端が titlebar と連続して見えることを確認する
- [x] 本文や Empty state の主要コンテンツが traffic light と衝突しない上余白を確保する
- [x] ウインドウドラッグ可能領域を損なっていないことを確認する
- [x] light / dark の両方で分離線や不自然な帯が残らないことを確認する

#### Phase 2 完了条件

- [x] どの画面状態でも「別バー感」が大幅に減っている
- [x] 上端の見え方が stillmd の静けさと整合している
- [x] ウインドウ操作感に退行がない

### Phase 3: タイトルは残しつつファイルアイコンを抑制する

目的: タイトルはファイル名のみ表示し、可能なら proxy icon を消す

- [x] 現状のファイルアイコン表示が `representedURL` 依存であることを確認する
- [x] `representedURL` を外しても duplicate detection と bring-to-front が成立する実装へ置き換える
- [x] タイトルがファイル名のみ表示されることを確認する
- [x] アイコンが非表示になることを確認する
- [x] もし macOS 標準挙動上アイコン抑制が完全でない場合、最小妥協案を整理する

#### Phase 3 完了条件

- [x] タイトルがファイル名だけになっている
- [x] ファイルアイコンが消える、または消せない理由と代替案が明確
- [x] 既存の open / reopen / duplicate focus 挙動が維持される

### Phase 4: Find bar の同化

目的: Find bar を「別カード」ではなく同じ面に溶け込む補助 UI へ調整する

- [x] Find bar の背景色をプレビュー背景と同系へ揃える
- [x] 線・角丸・padding を静かな方向へ調整する
- [x] Find bar が表示されても titlebar と本文の間に別帯が生まれないことを確認する
- [x] `⌘F` で開く、`Esc` で閉じる既存体験を維持する
- [x] 検索結果表示、前後移動、フォーカス挙動にデグレがないことを確認する

#### Phase 4 完了条件

- [x] Find bar が本文面に自然に載って見える
- [x] 常設ツールバー感がない
- [x] 既存の検索機能に退行がない

### Phase 5: テスト・回帰確認

目的: 見た目の改善が既存機能や複数導線を壊していないことを確認する

- [x] `swift build`
- [x] `swift test`
- [x] 必要な unit test を追加または更新する
- [x] Empty state で一体化が成立していることを目視確認する
- [x] Markdown preview で一体化が成立していることを目視確認する
- [x] Find bar 表示時も背景が分離しないことを目視確認する
- [x] light / dark / System で破綻しないことを確認する
- [x] Finder `Open With`、Dock drop、`⌘O`、重複ファイル再オープンで既存挙動が崩れないことを確認する
- [x] 長い Markdown を開いたときも本文可読性とスクロールが保たれることを確認する
- [x] 必要に応じて `./scripts/build-app.sh --release` で配布ビルドを再生成し、アプリ実機確認を行う

#### Phase 5 完了条件

- [x] build / test が通る
- [x] 主要導線で regression がない
- [x] 見た目と操作感の両方で意図した一体化が確認できる

---

## 6. テストケース

### 6.1 自動テスト

- `WindowManager` の duplicate detection と bring-to-front 補助ロジックが、新しい window registry 構造でも成立する
- `PendingFileOpenCoordinator` など既存挙動に影響がない
- `HTMLTemplate` や Markdown rendering 系テストが既存通り通る
- 追加する helper が pure なロジックを持つ場合、その単体テストを加える

### 6.2 手動確認

#### Empty state

- 起動直後の空画面で titlebar と背景が一体化して見える
- traffic light 周辺だけ別帯に見えない
- タイトル表現が静かで、Empty state コンテンツと衝突しない

#### Preview state

- Markdown を開いた直後に、上端が iTerm 的な一体面として見える
- 本文開始位置が不自然に遠すぎず、かつ traffic light と重ならない
- light / dark で境界線や段差が見えない

#### Find bar

- `⌘F` で Find bar を表示しても背景色が同化している
- Find bar だけ浮いたカードに見えない
- `Esc` で閉じたあとも上端に不要な帯が残らない

#### タイトル / アイコン

- タイトルはファイル名だけ表示される
- ファイルアイコンが非表示になる
- もし proxy icon を外した影響でタイトルバーの path menu が消えても、stillmd の思想上許容範囲か判断する

#### 既存導線

- `⌘O` で開く
- Finder の `Open With` で開く
- Dock icon へドラッグして開く
- 同じファイルを再度開いたとき、既存ウインドウが前面に来る

---

## 7. 想定リスク

1. `representedURL` を外すと、proxy icon だけでなく既存の bring-to-front 実装も失われる
2. titlebar 一体化設定によって、ドラッグ領域や本文上余白の扱いが不安定になる可能性がある
3. Empty state と Preview state の背景責務が別だと、片方だけ一体化が崩れる可能性がある
4. Find bar の同化を優先しすぎると、検索 UI の存在が分かりにくくなる可能性がある
5. macOS バージョン差分で titlebar 表現が微妙に異なる可能性がある

---

## 8. Step 2 での実施内容要約

- Window レベルで titlebar と content の一体化設定を導入する
- `WindowAccessor` / `WindowManager` を見直し、`representedURL` 依存を外しても既存 window 挙動が保てるようにする
- タイトルをファイル名だけに整え、proxy icon 抑制を試みる
- Preview / Empty state / Find bar の上端背景を共通トーンへ揃える
- build / test / 実機目視確認で仕上がりを検証する
- `swift build` / `swift test` / `./scripts/build-app.sh` / `./scripts/build-app.sh --release` を通過した
- 実機キャプチャで Empty state の unified chrome とファイルアイコン非表示を確認した
- Preview state はアプリ起動による目視確認を実施し、上端の一体化とタイトル表示を確認した
