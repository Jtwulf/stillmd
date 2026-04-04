# stillmd 洗練化 実装計画書

## 概要

stillmd を `preview-only / ミニマル / 静けさ / 軽量性` の思想に沿って洗練させる。
今回の Step 2 では、土台修正・体験改善・`Find in Page`・Settings を実装対象とする。

## Step2 方針確定事項

- 追加機能:
  - `Find in Page` (`⌘F`)
  - Settings (`Theme: System / Light / Dark`, `Text scale`)
- スクロール位置保持は中途半端な状態をやめ、正式に実装し切る
- 見た目は GitHub 風の情報密度を少し弱め、静かな読書アプリ寄りに寄せる
- 常設 sidebar / 常設 toolbar / 見出しジャンプは今回対象外

---

## Phase 1: 土台の整合性を揃える

- [x] `Package.swift` / README / `Info.plist` / build script の macOS 要件を統一する
- [x] source `Info.plist` を正本として `.app` 生成時に再利用する
- [x] `OpenWindowInjector.swift` など未使用コードを整理する
- [x] `WindowManager` のコメントと責務を現実の実装に合わせる
- [x] Markdown 用の file type / open panel 設定を共通化する
- [x] スクロール位置保持をイベント送信・保存・復元まで実装する
- [x] `swift build`
- [x] `swift test`

## Phase 2: 描画品質と再読み込み体験を磨く

- [x] `preview.css` のタイポグラフィ、余白、コードブロック、表、引用の静けさを調整する
- [x] Empty state を静かに洗練する
- [x] FileWatcher / 復旧挙動を改善し、一時消失から自然に戻るようにする
- [x] エラー時も可能なら直前の内容を保ち、邪魔な断絶を減らす
- [x] `swift build`
- [x] `swift test`

## Phase 3: stillmd に適合する機能を追加する

- [x] `⌘F` で最小検索バーを開ける
- [x] 検索結果件数と前後移動を実装する
- [x] 検索 UI が常設化しないようにする
- [x] Settings を macOS 標準導線で開ける
- [x] Theme を `System / Light / Dark` で切り替えられる
- [x] `Text scale` を数値スライダーで調整できる
- [x] テーマと文字サイズが preview に即時反映される
- [x] `swift build`
- [x] `swift test`

## Phase 4: 検証・配布・運用を固める

- [x] README を公開向けに更新する
- [x] release `.app` を再生成する
- [x] `.app` サイズ、アイコン、document type、表示名を確認する
- [x] 計画書の進捗を最終状態へ更新する
- [x] セルフレビューを行う
- [x] `swift build`
- [x] `swift test`
- [x] `./scripts/build-app.sh --release`

## Review Cycle メモ

- [x] `kiro` レビューを依頼した
- [x] `codex` レビューを依頼した
- [x] `kiro-cli` 未導入のため `kiro` は review unavailable だった
- [x] GitHub 上の `codex` 応答は得られなかったため CLI fallback を試した
- [x] `codex review --base main` は認証エラーを含み、最終 verdict を返せなかった

## Step 2 完了条件

- [x] 全 Phase のチェックリストが完了している
- [x] 実装・テスト・配布確認が完了している
- [x] commit / push / PR / review cycle まで完了している
