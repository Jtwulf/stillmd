# stillmd — cold start 時の Finder 連携初回オープン修正 実装計画書

## 0. メタ情報

| 項目 | 内容 |
|------|------|
| 対象リポジトリ | **stillmd** |
| 対象症状 | stillmd が未起動の状態で Finder から `.md` / `.markdown` をダブルクリックすると、初回は `empty status` が表示され、同じファイルをもう一度 Finder から開いたときだけプレビューが出る |
| 期待動作 | stillmd 未起動時でも、Finder または LaunchServices 経由で Markdown を開いた瞬間に、最初の 1 回で対象ファイルのプレビューが表示される |
| 前提コマンド | `swift build`、`swift test`、必要に応じて `./scripts/build-app.sh` |
| 既存の重要経路 | `StillmdApp.swift`、`StillmdDocumentWindow.swift`、`PendingFileOpenCoordinator.swift`、`RootView.swift`、`WindowManager.swift` |

## 1. 状況整理

### 1.1 ユーザー要求

- `stillmd` を Markdown のデフォルト起動アプリに設定済み
- **アプリ未起動**の状態で Finder から Markdown を開くと、最初は empty state になる
- その後に **同じ操作をもう一度**行うと、初めてプレビューが表示される
- したがって warm state のファイルオープンではなく、**cold start 専用の初回受け渡し不良**が主題

### 1.2 現行コードから確認できた事実

1. `AppDelegate.applicationDidFinishLaunching` は、起動直後に `DocumentWindowFactory.openDocument(...)` を**無条件で 1 回**呼ぶ
2. `AppDelegate.application(_:open:)` は受け取った Markdown URL を `PendingFileOpenCoordinator.enqueue(...)` に積む
3. 起動中のウィンドウ側では `RootView.onAppear` と `pendingChangeID` の監視で `pendingFileOpenCoordinator.drain()` を消費する
4. つまり現在は、外部オープンを
   - まず空ウィンドウを作る
   - 後から pending queue を View 側で拾って `documentSession.fileURL` を差し込む
   という **二段構え**で処理している

### 1.3 ここから言えること

- warm state で 2 回目に成功するなら、Markdown の描画経路そのものより、**起動直後の URL 受け渡しタイミング**に問題がある可能性が高い
- 特に以下の 2 点が有力
  - cold start 時のファイル URL が `application(_:open:)` だけでは取り切れていない
  - 受け取れていても、**空ウィンドウを先に出す設計**のせいで、最初の表示責務が empty state に寄っている

## 2. 関連コードのキャッチアップ結果

### 2.1 `stillmd/App/StillmdApp.swift`

- `applicationDidFinishLaunching` で `openNewDocumentHandler` を配線したあと、常に空ドキュメント窓を 1 つ生成している
- `application(_:open:)` では pending queue に積むだけで、cold start の最初のファイルを **直接 `initialURL` として窓生成**していない

### 2.2 `stillmd/App/PendingFileOpenCoordinator.swift`

- 単純な FIFO 的キューで、`enqueue` と `drain` しか持たない
- 「これは cold start 直後の初回起動要求か」「起動済みアプリへの追加オープンか」という文脈を保持していない

### 2.3 `stillmd/Views/RootView.swift`

- `documentSession.fileURL == nil` なら empty state を描画する
- pending queue を消費できた場合は `documentSession.fileURL` を埋めるが、責務が View 側に寄っている
- つまり初回ファイルオープン成功が、App レベルではなく **View の `onAppear` / `onChange` のタイミング**に依存している

### 2.4 `stillmd/App/StillmdDocumentWindow.swift`

- `DocumentWindowFactory.openDocument(initialURL:)` 自体はすでに存在し、**最初からファイル付きで窓を生成する能力はある**
- にもかかわらず AppDelegate 側が cold start 初回オープンでそれを十分活用していない

### 2.5 `stillmd/Services/WindowManager.swift`

- 重複検知と bring-to-front はここで担っている
- 既存の multi-window / duplicate detection を壊さないため、今回の修正は `WindowManager` の契約を保ったまま App 起動経路を整えるのが筋

## 3. 要件定義

### 3.1 機能要件

1. stillmd 未起動時に Finder から Markdown を開いた場合、最初の 1 回でプレビュー表示に到達する
2. cold start 時の最初のファイルは、empty state を経由せず、**可能な限り `initialURL` 付きのドキュメント窓**として開く
3. 複数ファイルが同時に渡された場合も、先頭 1 件は初期窓、それ以外は追加窓として処理できる
4. 起動済みアプリに対する Finder / Dock / `open` コマンド経由の追加オープンも維持する

### 3.2 非機能要件

1. preview-only の思想を守る
2. 起動速度を大きく落とさない
3. 既存の `⌘N`、`⌘O`、重複ファイル bring-to-front、Find bar、テーマ、text scale を壊さない
4. `swift build` / `swift test` を通す

## 4. 原因仮説

### H1. cold start のファイル URL が `application(_:open:)` だけでは安定して回収できていない

- LaunchServices / Finder 起動時は、アプリ起動済み時と URL 受け渡しの順序が異なる可能性がある
- 現実に「未起動時の初回だけ失敗」という症状は、この仮説と整合する

### H2. URL は届いているが、empty window 先行生成のせいで初回表示が空状態に固定される

- `applicationDidFinishLaunching` が無条件で空窓を開くため、ファイルオープン要求が View 側の queue 消費に依存する
- この構造は起動順序に弱い

### H3. cold start 専用の queue 消費タイミング race がある

- `RootView.onAppear` / `onChange` による drain は簡潔だが、起動初期のイベント順序に密結合
- 初回だけ missed signal になると、2 回目の Finder open で初めて `pendingChangeID` が動き、期待どおりに見える

## 5. 実装方針

### 基本方針

- **View ではなく App 起点で cold start の初回オープンを完結させる**
- 具体的には、起動時に渡された Markdown URL を AppDelegate 側で一度正規化し、**最初のウィンドウ生成時点で `initialURL` を渡す**
- pending queue は「起動後の追加オープン」や「複数同時オープンの残件処理」に寄せ、初回ファイル表示の主責務から外す

## 6. 実装 Phase

### Phase 1: cold start オープン経路の事実確認と責務整理

**目的**

- cold start 時に Finder/LaunchServices からファイル URL がどの経路で届くかを証拠ベースで確定する

**作業**

1. `AppDelegate` に最小限の診断ログまたは切り出し可能なテスト用フックを追加する
2. 以下の発火順を確認する
   - `applicationDidFinishLaunching`
   - `application(_:open:)`
   - 初回 `DocumentWindowFactory.openDocument(...)`
   - `RootView.onAppear`
3. 必要なら cold start で使われる別経路
   - launch arguments
   - Apple Event / open document 系
   の有無を確認する
4. 計測後、Step 2 実装では常時ノイズにならない形に整理する

**完了チェックリスト**

- [x] cold start 時の URL 到達経路を 1 つ以上、証拠付きで特定できた
- [x] `application(_:open:)` だけで十分か、不十分かを判定できた
- [x] empty window が先に作られているかどうかを確認できた
- [x] 修正対象責務を `AppDelegate` / `PendingFileOpenCoordinator` / 新規 helper のどこに置くか決められた

### Phase 2: 起動時オープン要求を App レベルで正規化する

**目的**

- cold start の初回オープン要求を、View の queue 消費ではなく App 起動責務として扱う

**作業**

1. 起動時に受け取った Markdown URL を保持する専用の小さなモデルまたは helper を導入する
2. その helper は少なくとも以下を扱えるようにする
   - 起動前後どちらで届いた URL でも一度バッファできる
   - 先頭 URL と残件 URL を分離できる
   - 既存の markdown validation を流用できる
3. `applicationDidFinishLaunching` では、起動要求がある場合
   - 空窓を無条件で作らない
   - **先頭 URL を `initialURL` として** `DocumentWindowFactory.openDocument(initialURL: ...)` する
4. 残件 URL は `WindowManager.openFile(_:)` または pending coordinator 経由で追加窓として処理する

**完了チェックリスト**

- [x] cold start 初回ファイルを `initialURL` 付きで窓生成できる
- [x] 起動要求があるときに空窓を先に出さない
- [x] 複数 URL のうち 2 件目以降も取りこぼさない
- [x] markdown 以外の URL は従来どおり無視できる

### Phase 3: warm state と既存 open 経路の整合を取る

**目的**

- cold start 修正で既存の Finder / Dock / `⌘O` / duplicate detection を壊さない

**作業**

1. 起動済みアプリへの `application(_:open:)` は従来どおり動作することを保つ
2. `PendingFileOpenCoordinator` が引き続き必要なら責務を縮小する
   - cold start 初回表示ではなく、追加オープンの一時バッファに限定する
3. `applicationShouldHandleReopen` は、可視窓がないときだけ空窓を作る現在の責務を維持する
4. `WindowManager` の重複検知と bring-to-front の契約を維持する

**完了チェックリスト**

- [x] 起動済み状態で Finder から別 Markdown を開ける
- [x] 同一ファイル再オープン時に duplicate window を増やさず bring-to-front できる
- [x] `⌘N` と `⌘O` が従来どおり使える
- [x] Dock drop や `NSWorkspace` フォールバックを壊していない

### Phase 4: テスト追加とリグレッション拘束

**目的**

- 今回の cold start バグを再発しにくくする

**作業**

1. pure Swift で検証できる単位にロジックを切り出す
2. 追加テスト候補
   - 起動時 URL バッファが先頭 1 件と残件を正しく分離する
   - markdown 以外を除外する
   - 起動要求あり時は空窓生成分岐に入らない
   - 起動要求なし時だけ空窓生成に入る
   - 複数ファイル受け取り時の順序保証
3. 既存テストとの整合
   - `PendingFileOpenCoordinator` テスト
   - `WindowManager` テスト
   - 既存の preview / find / window 系テスト

**完了チェックリスト**

- [x] 新規ロジックに対応する unit test を追加した
- [x] 既存の `PendingFileOpenCoordinator` / `WindowManager` テストと矛盾しない
- [x] `swift test` が全件成功する
- [x] `swift build` が成功する

### Phase 5: E2E と手動確認

**目的**

- 実際の Finder/LaunchServices 経路で「一発で開く」ことを確認する

**確認ケース**

1. `swift build`
2. `swift test`
3. `./scripts/build-app.sh`
4. アプリを完全終了した状態で、以下を確認
   - Finder から `.md` をダブルクリックして 1 回でプレビュー表示
   - Finder から `.markdown` をダブルクリックして 1 回でプレビュー表示
   - `open path/to/file.md` でも default app として 1 回で表示
   - `open -a build/stillmd.app path/to/file.md` でも表示
5. 起動済み状態で、別ファイル・同一ファイル・複数ファイルの open 挙動を確認

**完了チェックリスト**

- [x] cold start + Finder ダブルクリックで empty state を経由せず表示できる
- [x] `.md` / `.markdown` の両方で再現しない
- [x] warm state の追加オープンも維持される
- [x] multi-window / duplicate detection が崩れていない

## 7. 変更対象の第一候補

- `stillmd/App/StillmdApp.swift`
- `stillmd/App/PendingFileOpenCoordinator.swift`
- `stillmd/App/StillmdDocumentWindow.swift`
- `stillmd/Views/RootView.swift`
- `stillmd/Services/WindowManager.swift`
- `stillmdTests/StillmdTests.swift`

## 8. リスク

1. cold start 対応のために open 経路を増やしすぎると、warm state と二重処理になる
2. empty state を出さないことだけに寄せると、複数ファイル起動時の残件処理を落とす可能性がある
3. AppDelegate にロジックを寄せすぎると、テスト不能な構造になる

## 9. リスク緩和

1. 起動要求の正規化を小さな pure Swift helper に寄せる
2. `initialURL` で直接開く責務と、残件を追加窓へ渡す責務を明確に分ける
3. manual E2E だけでなく unit test でも起動分岐を拘束する

## 10. 完了の定義

1. stillmd 未起動時に Finder から Markdown を開くと、最初の 1 回で対象ファイルのプレビューが出る
2. 起動直後に empty state のまま取り残されない
3. 起動済み状態での open 挙動、複数ウィンドウ、duplicate detection、`⌘N`、`⌘O` を壊さない
4. `swift build` / `swift test` が成功する
5. `./scripts/build-app.sh` 後の `.app` でも cold start の Finder/LaunchServices 経路を確認できる
