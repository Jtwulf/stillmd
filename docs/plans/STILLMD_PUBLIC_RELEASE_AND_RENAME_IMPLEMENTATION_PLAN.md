# stillmd 一般公開整備 / GitHub Releases ZIP 配布 / 全面改名 実装計画書

## 概要

stillmd は preview-only / ミニマル / 静けさを重視する macOS 向け Markdown viewer であり、一般公開時の repo もその思想に沿って、静かで分かりやすく、余計な迷いがない状態であるべき。

現状の repo は、アプリ本体の実装品質や build / test の健全性は十分に高い一方で、公開リポジトリとして見ると次のズレがある。

- `README.md` が簡潔すぎて、初見ユーザーに価値や導入方法が十分伝わらない
- `README.md` に `MIT` とあるが、repo 直下に `LICENSE` ファイルが存在しない
- 同梱している第三者ライブラリ `marked.js` / `highlight.js` の notice 導線がない
- Issue / PR を受け付ける前提の `.github/` 整備が不足している
- GitHub Releases で `stillmd.app` を含む `.zip` を配る前提の配布手順・成果物定義が不足している
- repo 名・アプリ名は `stillmd` だが、Step 1 時点では Swift Package / target / module / ディレクトリ名の中心が旧内部名称 `MarkdownPreviewer` のままで、公開名称と内部名称がずれていた

今回の目的は、stillmd を一般公開可能な repository として整え、GitHub Releases で `stillmd.app` を含む `.zip` を配布できる状態に持っていくこと、そして旧内部実装名 `MarkdownPreviewer` を `stillmd` へ全面改名して名称の一貫性を回復することにある。

なお、ユーザー確認済み前提は次の通り。

- 公開範囲は一旦すべて公開
- Issue / PR は受け付ける
- ライセンスは `MIT`
- 配布は GitHub Releases で `stillmd.app` を含む `.zip` を配る
- Apple Developer Program は**未加入**
- 改名は表示名だけでなく、Swift Package / target / module / フォルダ名まで**全面改名**

Apple Developer Program 未加入のため、Developer ID 署名および notarization は今回の実装スコープ外とする。
その代わり、**未署名・未 notarize の `stillmd.app` を `.zip` にまとめて配布すること**、初回起動時に Gatekeeper 回避手順が必要になりうることを README / Release Notes に明記する。

---

## 1. キャッチアップ結果

### 1.1 現状の repo 構成

- 公開向け README は [README.md](../../README.md) に存在する
- ライセンス本文ファイル `LICENSE` は repo 直下に存在しない
- `.github/` ディレクトリは現状存在しない
- build スクリプトとして [scripts/build-app.sh](../../scripts/build-app.sh) が存在し、`build/stillmd.app` を生成できる
- App bundle の表示名・実行バイナリ名・Bundle Identifier は [stillmd/Info.plist](../../stillmd/Info.plist) 上では `stillmd` / `com.jtwulf.stillmd`
- 一方で Step 1 時点では Swift Package 名、target 名、テスト target 名、ソースディレクトリ名は `MarkdownPreviewer` 中心だった

### 1.2 現状の README

- [README.md](../../README.md) は英語で統一されており、これは `docs/rules/06-doc-governance.md` と整合する
- ただし公開 repo としては、以下が不足している
  - プロダクトの価値説明
  - スクリーンショットや見た目の導線
  - Releases 配布を前提にした install 導線
  - unsigned / unnotarized app の注意点
  - contribution / issue / support の導線
  - third-party licenses の案内

### 1.3 現状のビルド・テスト

- `swift build` は成功済み
- `swift test` は成功済み
- したがって、現状の codebase は公開整備に入る前提として十分健全

### 1.4 同梱第三者ライブラリ

- [stillmd/Resources/marked.min.js](../../stillmd/Resources/marked.min.js)
  - header comment から `marked v15.0.12`
  - license は `MIT`
- [stillmd/Resources/highlight.min.js](../../stillmd/Resources/highlight.min.js)
  - header comment から `Highlight.js v11.9.0`
  - license は `BSD-3-Clause`

### 1.5 公開時の制約

- Apple Developer Program 未加入のため、Developer ID 署名・notarization・Stapler 前提の完全な macOS 配布体験は今回実現できない
- ただし GitHub Releases への `.zip` 配布自体は可能
- その場合は、README / Release Notes に「未署名・未 notarize」であることと、必要な起動手順を案内する必要がある

---

## 2. 要件整理

### 2.1 主要件

- stillmd を一般公開 repo として読める README に整える
- `MIT` ライセンスを正式に適用し、GitHub に認識される状態にする
- third-party notices を整備し、同梱ライブラリのライセンス責務を果たす
- Issue / PR を受け付ける前提の `.github/` 整備を行う
- GitHub Releases で `stillmd.app` を含む `.zip` を配布するための build / packaging / release 手順を定義する
- 旧内部名称 `MarkdownPreviewer` を `stillmd` へ全面改名する

### 2.2 非機能要件

- stillmd の思想に反する過剰な公開運用ドキュメント化を避ける
- README は公開向け英語ドキュメントとして保ち、内部ルール docs と役割を混ぜない
- 既存 build / test の健全性を壊さない
- Finder での `.md` / `.markdown` 関連付けや App bundle の動作を壊さない
- 将来の signed / notarized release へ移行しやすい構成にしておく

### 2.3 今回の明示的なスコープ

- README 再構成
- `LICENSE` 追加
- `THIRD_PARTY_NOTICES.md` 追加
- `.github/` 追加
- GitHub Releases 用の配布導線整備
- `MarkdownPreviewer` → `stillmd` の全面改名

### 2.4 今回のスコープ外

- Apple Developer Program 加入
- Developer ID 署名
- notarization
- Mac App Store 配布
- コード署名用シークレットを使った GitHub Actions 自動 notarization

---

## 3. 公開戦略と設計方針

### 3.1 README の基本方針

README は「公開 repo の入口」であり、初見ユーザーが 30 秒で次を理解できることを目標とする。

1. stillmd が何のアプリか
2. どんな体験を目指しているか
3. どうやって試すか
4. 何ができて何をしないか
5. どこに issue / PR を出せばよいか

内部設計思想の正本はあくまで日本語 docs に置き、README には必要最小限の案内のみ残す。

### 3.2 ライセンス方針

- repo 本体コードは `MIT`
- third-party code は各 upstream license に従う
- `LICENSE` は stillmd 本体のライセンス本文
- `THIRD_PARTY_NOTICES.md` は bundled dependency の帰属とライセンス案内

### 3.3 Release 配布方針

- GitHub Releases では、ユーザーが扱いやすいように `stillmd.app` をまとめた `stillmd-<version>-macos.zip` を第一候補とする
- Release Notes には以下を明記する
  - 対応 macOS バージョン
  - 未署名・未 notarize であること
  - 初回起動時の回避手順
  - checksum があればその値

### 3.5 Versioning 方針

- 最初の公開版は `v0.1.0` を基本候補とする
- これは「最初に外へ出す配布点」を作るための番号であって、完成度の宣言ではない
- 公開直前に大きな変更が残るなら、無理に `v0.0.1` に寄せず `v0.1.0` で区切るほうが整理しやすい
- 以後は小さな修正なら `v0.1.1`、機能追加なら `v0.2.0` のように進める

### 3.6 ZIP の中身

- 配布物は `stillmd.app` をそのまま zip 化したもの
- zip の中には、`stillmd.app` バンドルが丸ごと入る
- ユーザーが触る単位は `.zip` ではなく、その中の `stillmd.app`
- Release からは `stillmd-<version>-macos.zip` をダウンロードして解凍し、`stillmd.app` を起動する
- zip にはアプリ本体以外の余計なインストーラやランチャーは含めない

### 3.4 改名方針

全面改名は、公開ブランドと内部実装名のズレを解消するために行う。
ただし Finder 関連付け・Bundle Identifier・テスト・resource bundle 名・build script が広く影響を受けるため、**Phase を分けて一気に整える**必要がある。

---

## 4. 変更対象の想定

### 4.1 ドキュメント

- [README.md](../../README.md)
- `LICENSE`（新規）
- `THIRD_PARTY_NOTICES.md`（新規）
- `.github/ISSUE_TEMPLATE/...`（新規）
- `.github/pull_request_template.md`（新規）
- `.github/SECURITY.md`（新規）

### 4.2 改名対象

- [Package.swift](../../Package.swift)
- 旧 `MarkdownPreviewer/` → [stillmd/](../../stillmd)
- 旧 `MarkdownPreviewerTests/` → [stillmdTests/](../../stillmdTests)
- `import` / `@testable import`
- build script 内の binary / bundle / path 名
- docs 内のファイルパス参照

### 4.3 Release 導線

- [scripts/build-app.sh](../../scripts/build-app.sh)
- 必要なら release packaging script（新規）
- 必要なら `.github/workflows/release.yml` 等の雛形

---

## 5. 実装方針

### Phase 1: 公開前の名称・依存・責務を棚卸しする

目的: 何を変えるべきか、何を維持すべきかを明確にする

- [x] 旧名称 `MarkdownPreviewer` が現れる箇所を repo 全体で洗い出した
- [x] Swift Package 名 / executable target 名 / test target 名 / source directory 名 / resource bundle 名の相互依存を整理した
- [x] Finder 関連付けや `Info.plist` 上の document type が、改名しても維持すべき責務であることを確認した
- [x] build script がどの binary 名・bundle 名に依存しているかを明確にした
- [x] third-party bundled assets のバージョン・ライセンス種別・notice 必要性を明文化した
- [x] repo 直下・`docs/`・隠しディレクトリのうち、公開ノイズになるものを整理した（`.serena/` を ignore 対象として追加）

#### Phase 1 完了条件

- [x] 改名の影響範囲が説明できる
- [x] 追加すべき公開ファイルの一覧が確定している
- [x] third-party license 対応方針が明文化されている

### Phase 2: `MarkdownPreviewer` を `stillmd` へ全面改名する

目的: 公開ブランドと内部構造の名称を一致させる

- [x] `Package.swift` の package 名を `stillmd` へ変更した
- [x] executable target 名を `stillmd` へ変更した
- [x] test target 名を `stillmdTests` へ変更した
- [x] ソースディレクトリ `MarkdownPreviewer/` を `stillmd/` へ変更した
- [x] テストディレクトリ `MarkdownPreviewerTests/` を `stillmdTests/` へ変更した
- [x] `@testable import MarkdownPreviewer` など module 参照を新名称へ更新した
- [x] build script 内の binary path / bundle path / app bundle 生成処理を新名称へ合わせて更新した
- [x] docs / plans / rules 内のパス参照や名称言及を必要範囲で更新した
- [x] resource bundle 名の変化により runtime loading が壊れていないことを `swift build` / `.app` 生成で確認した
- [x] 既存 app 表示名 `stillmd` / bundle identifier `com.jtwulf.stillmd` と矛盾しないことを確認した

#### Phase 2 完了条件

- [x] repo 内の主要名称が `stillmd` に統一されている
- [x] build script が改名後も `.app` を生成できる
- [x] `swift build` / `swift test` が改名後も通る
- [x] `.md` ファイルの viewer としての基本動作が維持される

### Phase 3: 公開向け README とライセンス文書を整備する

目的: 初見ユーザー・利用者・再配布者に必要な情報を過不足なく渡す

- [x] `README.md` 冒頭を stillmd の価値説明中心に再構成した
- [x] README に image 導線として app icon を追加した
- [x] README に `Why stillmd` / `Non-goals` を入れ、preview-only の境界を明確にした
- [x] README に install 方法として GitHub Releases ZIP 導線を追加した
- [x] README に source build 手順を、改名後の package / target 名に合わせて更新した
- [x] README に unsigned / unnotarized app の注意事項を追加した
- [x] README に issue / PR 歓迎の導線を追加した
- [x] repo 直下に `LICENSE` を追加し、MIT 本文を配置した
- [x] repo 直下に `THIRD_PARTY_NOTICES.md` を追加した
- [x] `THIRD_PARTY_NOTICES.md` に `marked` と `highlight.js` の名称・バージョン・出典・ライセンス種別・ライセンス本文参照先を記載した

#### Phase 3 完了条件

- [x] README だけで導入・利用・貢献の入口が理解できる
- [x] GitHub が `LICENSE` を認識できる標準ファイル名・本文配置になっている
- [x] third-party bundled assets の扱いが説明できる
- [x] preview-only の思想が README 上でも誤解なく伝わる

### Phase 4: `.github/` と公開運用ファイルを整備する

目的: public repo としての受け皿を最小限で用意する

- [x] `.github/ISSUE_TEMPLATE/bug_report.md` を追加した
- [x] `.github/ISSUE_TEMPLATE/feature_request.md` を追加した
- [x] `.github/ISSUE_TEMPLATE/config.yml` を追加し、blank issue は許可したまま運用できるようにした
- [x] `.github/pull_request_template.md` を追加した
- [x] `.github/SECURITY.md` を追加した
- [x] `SECURITY.md` には、Apple Developer Program 未加入前提と脆弱性報告時の期待導線を簡潔に記載した
- [x] 公開時に不要なローカル補助ディレクトリ（例: `.serena/`）の扱いを決め、`.gitignore` を更新した
- [x] docs/plans や内部ルール docs を公開したままでも、README からの主導線が公開向け文書に留まるよう整理した

#### Phase 4 完了条件

- [x] Issue / PR の受け皿が揃っている
- [x] 脆弱性報告導線が存在する
- [x] 公開 repo に不要なローカルノイズが整理されている

### Phase 5: GitHub Releases 用の ZIP packaging 導線を整備する

目的: ユーザーが実際に試せる配布成果物を一貫した手順で作れるようにする

- [x] `scripts/build-app.sh --release` で release build の `.app` が生成できることを確認した
- [x] `.app` を release asset 用に zip 化する手順を `scripts/package-release.sh` と README に明記した
- [x] 配布ファイル名規則を `stillmd-vX.Y.Z-macos.zip` に定めた
- [x] checksum 生成手順を追加した
- [x] Release Notes 用の記述例を `.github/workflows/release.yml` の release body に用意した
- [x] unsigned / unnotarized app の初回起動手順を release 導線に明記した
- [x] 将来の notarization 対応が追加しやすいよう、build と package を別スクリプトに分離した

#### Phase 5 完了条件

- [x] ローカルで release asset を安定して生成できる
- [x] GitHub Releases に載せる成果物・説明文・注意事項が定義済み
- [x] 初見ユーザーがダウンロードから起動まで辿れる

### Phase 6: 回帰確認と公開前の最終点検を行う

目的: 整備作業がアプリ本体の挙動を壊していないことを確認する

- [x] `swift build`
- [x] `swift test`
- [x] `./scripts/build-app.sh`
- [x] `./scripts/build-app.sh --release`
- [x] 生成された `.app` を起動し、空状態でプロセスが正常起動することを確認した
- [x] `.md` ファイルをアプリへ渡して開けることを確認した
- [x] Finder `Open With` 相当の導線で `.md` / `.markdown` を開けることを `open -a` smoke で確認した
- [x] Drag & Drop / Dock icon open まわりは関連コード未変更であることと、ファイル起動 smoke で退行がないと判断した
- [x] `⌘F`、theme 変更、text scale 変更など既存主要機能は、関連実装未変更かつ既存テスト通過により退行がないと判断した
- [x] README 記載の build / install / release 手順が現実と一致していることを確認した
- [x] Release asset の zip 展開後に `stillmd.app` の構造が崩れていないことを確認した

#### Phase 6 完了条件

- [x] build / test / app packaging が通る
- [x] 主要利用導線に退行がない
- [x] 公開に必要な文書・配布物・導線が揃っている

---

## 6. テスト計画

### 6.1 自動確認

- [x] `swift build`
- [x] `swift test`
- [x] rename 影響が大きい箇所に対してテスト名・import 名の更新漏れがないことを確認した

### 6.2 パッケージング確認

- [x] debug build で `.app` 生成
- [x] release build で `.app` 生成
- [x] release asset zip 生成
- [x] zip 展開後の `.app` 構造確認と起動 smoke を実施

### 6.3 手動 E2E 確認

- [x] `open build/stillmd.app` 相当で起動
- [x] 空状態での起動 smoke
- [x] `.md` ファイルのオープン
- [x] `.markdown` ファイルのオープン
- [x] 画像参照を含む Markdown の open smoke
- [x] コードブロック / 表 / リストを含む Markdown の open smoke
- [x] サンプル Markdown 追記による自動リロード smoke
- [x] 検索 UI は関連コード未変更かつ既存テスト通過で退行がないと判断
- [x] theme / text scale 設定反映は関連コード未変更かつ既存テスト通過で退行がないと判断
- [x] 複数ファイルを開いたときのウィンドウ挙動は既存 WindowManager テスト通過で退行がないと判断

### 6.4 ドキュメント確認

- [x] README のコマンド・パス・名称が改名後の実態に一致する
- [x] LICENSE のファイル名と本文が GitHub / SPDX 相当認識の前提を満たす
- [x] THIRD_PARTY_NOTICES の記載が bundled versions と一致する
- [x] SECURITY / issue templates / PR template が GitHub 上で有効に働く前提になっている

---

## 7. 想定リスク

1. **全面改名による build break**
   - Swift Package target 名、resource bundle 名、test import、build script が広く連動しているため、部分改名は破綻しやすい

2. **docs の参照切れ**
   - `docs/rules/` や `docs/plans/` にはファイルパスが多数登場するため、rename 後に内部リンク切れが発生する可能性がある

3. **release packaging の実態と README の不一致**
   - 手順だけ書いて検証しないと、公開後の最初の利用者が詰まる

4. **unsigned / unnotarized app への問い合わせ増加**
   - Apple Developer Program 未加入の前提では避けられないため、README / Release Notes 側で先回りして説明する必要がある

5. **公開ノイズの残存**
   - `.serena/` のようなローカル補助物が public repo に残ると、初見ユーザーには意味不明なノイズになる

---

## 8. Step 2 で実施する作業の要約

- 旧 `MarkdownPreviewer` 系の package / target / module / directory を `stillmd` 系へ全面改名する
- build script と runtime resource loading が改名後も成立するよう修正する
- `README.md` を公開 repo 用に全面整理する
- `LICENSE` と `THIRD_PARTY_NOTICES.md` を追加する
- `.github/` の public repo 運用ファイルを追加する
- GitHub Releases に載せる `.app` / `.zip` 生成導線を整備する
- build / test / packaging / manual E2E まで確認し、一般公開可能な状態へ持っていく

---

## 9. 参考にした外部情報

- GitHub Docs: repository へライセンスを追加する方法
- GitHub Docs: public repository の contribution 導線（issue / PR template, security policy）
- Apple Developer documentation: App Store 外配布では署名・notarization が望ましいこと
- `marked` upstream license
- `highlight.js` upstream license

本計画では、上記の一般方針を踏まえつつ、**Apple Developer Program 未加入でも実行可能な公開整備**にスコープを限定する。
