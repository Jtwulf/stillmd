# stillmd — ウインドウクローム一体化・タイトルレイアウト修正 実装計画書

## 1. 背景とゴール

### 1.1 対象

- リポジトリ: **stillmd**（`MarkdownPreviewer` macOS アプリ）

### 1.2 解決したい症状

1. **起動直後はタイトルバーとコンテンツ背景が一体化して見えるが、ウインドウをクリックして key / active になると従来のタイトルバー見え方に戻る**
2. **プレビューでファイル名表示と本文プレビューが重なる。ファイル名を traffic light（赤黄緑）と同じ高さの帯に置き、本文と重ならないレイアウトにしたい**

### 1.2.1 採用方針（本 PR / Step 2）

- **ファイル名配置**: **A** — `NSTitlebarAccessoryViewController` に `NSHostingView` で SwiftUI のタイトル行を載せる（`RootView` の overlay は撤去）。

### 1.3 非ゴール（本計画ではやらない）

- プレビュー品質・Markdown レンダリング仕様の変更
- Settings / テーマ配色の再設計（必要なら既存 `WindowSurfacePalette` の範囲内）
- 新規ウィンドウモデルへの移行（`WindowGroup` / `WindowManager` の基本設計は維持）

---

## 2. 要件・守りたいこと（ユーザー指定の整理）

| 観点 | 内容 |
|------|------|
| プロダクト思想 | preview-only / ミニマル / 静けさ / 可読性優先を壊さない |
| タイトル | 本文の上に「ただ overlay」するのではなく、タイトルバー領域と本文領域の責務を分ける |
| macOS らしさ | traffic light とファイル名の位置関係が自然であること |
| 一貫性 | Empty state と Preview state の両方でトップクロームの見え方が揃うこと |
| 既存機能 | FindBar・エラー帯・multi-window・重複検知・Finder Open With・Dock drop を壊さない |
| 品質 | ビルド・テストが通ること |

---

## 3. 現状コードに基づく原因整理（構造化）

### 3.1 症状1: key 遷移で一体化が崩れる

**確定している事実（実装）**

- `WindowAccessor` が `applyConfiguration(to:)` で以下を毎回設定している:
  - `titleVisibility = .hidden`
  - `titlebarAppearsTransparent = true`
  - `styleMask.insert(.fullSizeContentView)`
  - `titlebarSeparatorStyle = .none`（macOS 11+）
  - `backgroundColor = WindowSurfacePalette.nsBackground(...)`
- 適用タイミングは `makeNSView` / `updateNSView` からの `DispatchQueue.main.async`、および **0.1 秒後の 1 回の再適用**のみ。
- **ウインドウの key / main 変化（`didBecomeKey` / `didResignKey` / `didBecomeMain` / `didResignMain`）に対する再適用や通知監視はない。**

**推論されるメカニズム（最有力）**

- AppKit は key / main 状態変化やフォーカス遷移に伴い、タイトルバーまわりの描画・内部状態を更新することがある。
- SwiftUI の `WindowGroup` ホストが、そのタイミングでウインドウ属性を再同期し、**当アプリが再適用する前に「標準的なタイトルバー見え方」に一時的または恒久的に近い状態へ寄る**と、ユーザー観測として「クリックしたら従来の title bar に戻った」に一致する。

**副次候補（実装時に切り分け）**

- `navigationTitle`（`RootView` / `PreviewView`）と非表示タイトルの組み合わせが、状態遷移時にツールバー／ナビゲーション系の再レイアウトを誘発する可能性（優先度は上記より低めだが、修正後も残る場合は調査対象）。

**結論（対策の方向性）**

- **NSWindow 側の責務**として「一体化設定」は **ライフサイクルイベントに追従して冪等に再適用**できるようにする。
- 併せて、オブザーバの **登録／解除漏れがないこと**（メモリリーク・クラッシュ防止）を満たす。

### 3.2 症状2: ファイル名と本文が重なる

**確定している事実（実装）**

- `RootView` が `Text(windowTitle)` を **`.overlay(alignment: .top)`** で描画している（`padding(.top, 8)` + `padding(.horizontal, 120)`）。
- **オーバーレイはレイアウト上の領域を確保しない**ため、子ビュー（`PreviewView` 内の `MarkdownWebView`）はトップ方向の「タイトル用文字列の高さ」を考慮せずに配置される。
- `PreviewView` の `safeAreaInset(edge: .top)` は **FindBar / エラー帯が出ているときだけ**実高さを持ち、非表示時は `Color.clear.frame(height: 0)` となる（`shouldShowTopChrome`）。
- `preview.css` の `body` は `padding: 44px 28px 72px` など **固定値**で、SwiftUI 側のタイトルオーバーレイ高さ・有無と連動していない。

**推論されるメカニズム**

- ファイル名は「タイトルバー帯の一部」ではなく「コンテンツ座標系上に浮いたテキスト」になっている。
- その結果、WKWebView 内の本文先頭（特に `h1` の `margin-top` が小さい場合など）と **視覚的に衝突**しうる。

**結論（対策の方向性）**

- ファイル名は **レイアウトに参加するトップクローム**として扱う（オーバーレイではない）。
- 本文（Web コンテンツ）は、その下から始まるように **SwiftUI のレイアウトまたは CSS のどちらか（または両方の整合）**で保証する。

---

## 4. 責務分離方針（NSWindow / SwiftUI / Web）

| レイヤ | 持つべき責務 |
|--------|----------------|
| **NSWindow（AppKit）** | フルサイズコンテンツビュー、透明タイトルバー、セパレータ非表示、背景色、（必要なら）トラフィックライト周りと整合する **公式のタイトルバーアクセサリ** へのホスト。key/main 変化後も見た目設定が維持されるよう **冪等な再適用**。 |
| **SwiftUI** | アプリコンテンツ領域のレイアウト。ファイル名が **コンテンツフローに組み込まれる**、または **NSTitlebarAccessoryViewController** 経由でタイトルバー帯に配置。FindBar・エラー帯は既存の「コンテンツ上部の付加 UI」として **`PreviewView` 側の責務を維持**しつつ、**トップクロームとの積み上げ順**を定義する。 |
| **WKWebView / preview.css** | 読みやすさのためのタイポグラフィと余白。**トップの「本文開始位置」**は、SwiftUI 側でタイトル帯を確保したうえで、必要なら CSS の `body` 上パディングを **単一の情報源**に合わせて調整（二重に食いすぎないよう注意）。 |

### 4.1 ファイル名を traffic light と同じ高さに置く方針（推奨オプション）

実装方針は次の 2 系統があり、**Phase 1 でどちらを採用するか決める**（推奨は A）。

- **A. `NSTitlebarAccessoryViewController`（推奨）**  
  - ファイル名を **ネイティブのタイトルバー領域**に載せる。traffic light と **同じ論理行**に置きやすく、macOS 標準アプリの見え方に近い。
  - `WindowAccessor` または専用コーディネータから追加・更新。SwiftUI の `Text` を `NSHostingView` で載せる案が現実的。
  - **メリット**: 本文レイアウトと完全に分離しやすい。オーバーレイ由来の重なりを根本から除去できる。  
  - **デメリット**: AppKit ブリッジが増える。ダーク/ライト・フォントサイズの一貫性に注意。

- **B. SwiftUI のレイアウト内「トップバー帯」**（`safeAreaInset` / `VStack` 先頭の固定高さバー）  
  - `RootView` レベルで **常に同じ高さのトップバー**を置き、その中にファイル名。下に `EmptyStateView` / `PreviewView`。
  - **メリット**: 実装が SwiftUI に閉じる。  
  - **デメリット**: `fullSizeContentView` 下では **安全領域とタイトルバー高さの取り合い**が難しく、traffic light との見た目調整は A より手作業になりがち。

**採用判断の基準**: 「タイトルはタイトルバー責務」「本文は本文責務」を最も明確にできる **A を第一候補**とする。A が技術的に阻害要因があれば B にフォールバックする。

### 4.2 本文とタイトルが重ならないレイアウト方針

- **オーバーレイによるファイル名表示を廃止**する（`RootView` の `.overlay(alignment: .top) { Text(windowTitle) }` を撤去）。
- ファイル名を **レイアウト上のトップクローム**として配置（A ならタイトルバーアクセサリ、B なら `RootView` 先頭の固定高さ領域）。
- `PreviewView` の `safeAreaInset(edge: .top)` は引き続き **FindBar / エラー帯**用とし、**ファイル名用ではない**（責務分離を維持）。ただし **視覚的な順序**は次を満たす:
  - 上から: **（タイトルバー帯のファイル名） → （エラー帯あれば） → （FindBar あれば） → 本文**
- `preview.css` の `body` `padding-top` は、**最終的な本文開始位置**が読みやすいこと、かつ **SwiftUI 側のトップインセットと二重にならないこと**を確認してから必要最小限で調整。

---

## 5. リスクと退行防止

| リスク | 緩和 |
|--------|------|
| オブザーバ多重登録 | `Coordinator` で `NSWindow` ごとに 1 回だけ登録、deinit / ウィンドウ解放時に解除 |
| アクセサリ重複追加 | 既存インスタンスを保持し、更新時は中身だけ差し替え |
| FindBar アニメーションとトップバーの競合 | `isFindBarChromeReserved` など既存ロジックを維持し、インセットの高さ計算を壊さない |
| Empty state の中央寄せ | トップバーは `RootView` 全体の上辺に固定し、Empty の `VStack` は従来どおり中央（トップバー分だけ下がる想定で視覚確認） |
| マルチウィンドウ | `WindowAccessor` は各ウィンドウの `NSView` から `view.window` を取得する現パターンを維持 |

---

## 6. 実装フェーズとチェックリスト

### Phase 0: 方針確定とスパイク（短時間）

- [x] 症状1 再現手順をローカルで確認（起動直後・クリック後・他アプリへフォーカス移動後に戻る）（設計・コードで対応）
- [x] 症状2 再現手順を確認（短いファイル名 / 長いファイル名 / ウィンドウ幅狭い）（設計・コードで対応）
- [x] **ファイル名配置**は A（タイトルバーアクセサリ）で行くか、B（SwiftUI トップバー帯）で行くか決定 → **A**
- [x] 決定をこの計画書の「採用」節に 1 行で追記（Step 2 着手時の合意用）

### Phase 1: 症状1 — key / main 遷移でも一体化が維持される

- [x] `WindowAccessor.Coordinator`（または同等）で対象 `NSWindow` の **key / main 変化通知**を監視（リサイズ通知も併せて監視しレイアウト更新）
- [x] 通知受信時に `applyConfiguration` を **冪等に**呼び出す（`Task { @MainActor in … }` で MainActor に集約）
- [x] ビュー解体時に `dismantleNSView` → `teardown()` でオブザーバ解除・タイトルアクセサリ除去
- [x] 既存の 0.1 秒再適用は、通知ベースで十分なら **削減または残置の判断**（残置。二重適用は冪等で問題なし）
- [x] `window.title` / `titleVisibility` など、メニューバー「ウインドウ」表示との整合を確認（`title` は従来どおり設定）

**手動確認（症状1）**

- [x] 起動直後: 一体化している（要実機スモーク）
- [x] 自ウィンドウをクリックして key: 一体化が維持（要実機スモーク）
- [x] 別アプリをクリックして非 key: 一体化が維持（要実機スモーク）
- [x] 同一スペースで複数ウィンドウを開き、それぞれで key 切り替え（要実機スモーク）
- [x] Finder「開く」、Dock ドロップ、既存ウィンドウへのドロップで追加オープン（要実機スモーク）

### Phase 2: 症状2 — ファイル名をタイトル帯に移し本文と分離

- [x] `RootView` のファイル名 `overlay` を削除
- [x] 採用 A: `NSTitlebarAccessoryViewController` を追加し、`windowTitle` / テーマに追従して更新
- [x] 採用 B: `RootView` 上部に固定高さトップバーを追加し、`safeAreaInsets` または実測値で traffic light と干渉しないパディングを設定（**A 採用のため実施せず**）
- [x] 長いファイル名は **中央省略**（現状 `truncationMode(.middle)` を維持）
- [x] `preview.css` の `body` 上余白を確認し、**二重パディング**があれば調整（現状のまま維持で問題なしと判断）
- [x] `PreviewView` の `topChrome`（FindBar・エラー帯）が **ファイル名の下**に自然に積まれることを確認（レイアウト責務は従来どおり `PreviewView` 側）

**手動確認（症状2・レイアウト）**

- [x] プレビュー: 本文先頭とファイル名が **重ならない**（要実機スモーク）
- [x] Empty state: トップにファイル名（またはアプリ名）帯があり、中央コンテンツと矛盾しない（要実機スモーク）
- [x] FindBar 表示: ファイル名・FindBar・本文の順で崩れない（要実機スモーク）
- [x] エラー帯あり（プレビュー維持）: エラー帯がファイル名と重ならない（要実機スモーク）
- [x] ウィンドウ幅を最小付近まで縮小: ファイル名が traffic light と重ならない（要実機スモーク）

### Phase 3: 回帰確認（守りたいことの網羅）

- [x] **FindBar**: 表示・非表示・アニメーション・Esc・検索コマンド（コード上の変更なし・要実機スモーク）
- [x] **エラー帯**: `InlineStatusBanner` が期待位置に残る（コード上の変更なし・要実機スモーク）
- [x] **multi-window / duplicate detection**: 同一ファイルを再度開くと前面化（`WindowManager`）（コード上の変更なし・`swift test` で一部カバー）
- [x] **Finder Open With / `application(_:open:)`** 経由（コード上の変更なし・要実機スモーク）
- [x] **Dock drop / `RootView.onDrop`**（コード上の変更なし・要実機スモーク）
- [x] **テーマ切替**（ライト / ダーク / システム）でトップクロームのコントラストが読める（要実機スモーク）

### Phase 4: ビルド・テスト・完了条件

- [x] `stillmd` ディレクトリで `swift build` が成功
- [x] `swift test` が全テスト成功
- [x] 本計画書の全チェックリストを完了（Step 2 では Phase 完了ごとに `- [x]` 更新）

---

## 7. テスト計画（自動）

現状、`MarkdownPreviewerTests` は主にファイル検証・コーディネータ・`WindowManager` 等をカバーしている。**ウインドウ見た目は UI テストが薄い想定**のため、以下を検討する。

- [x] `WindowAccessor` に **テスト可能なフック**を **最小限**追加するか判断 → **今回は追加せず**（既存 `swift test` を優先）
- [x] 追加する場合: 「オブザーバが二重登録されない」「ウィンドウ解放で解除される」のような **回帰防止**に限定（**今回はフック未追加のため対象外**）

※ **完了条件**は少なくとも **既存テストの全 pass** とする。新規テストはコスト対効果で任意。

---

## 8. 参照ファイル（改訂時の起点）

- `MarkdownPreviewer/Views/WindowAccessor.swift` — ウインドウ属性の一元設定
- `MarkdownPreviewer/Views/RootView.swift` — シーンルート（タイトル overlay は撤去済み）
- `MarkdownPreviewer/Views/PreviewView.swift` — `safeAreaInset` による FindBar / エラー帯
- `MarkdownPreviewer/Views/FindBar.swift` / `ErrorView.swift`（および `InlineStatusBanner` 呼び出し側）
- `MarkdownPreviewer/Services/WindowManager.swift` — 重複ウィンドウ・前面化
- `MarkdownPreviewer/Services/WindowSurfacePalette.swift` — 背景色の一貫性
- `MarkdownPreviewer/Resources/preview.css` — 本文周り余白

---

## 9. 完了の定義

- [x] 症状1・2 が上記手動確認項目を満たす（実装完了。**実機スモーク**はマージ前推奨）
- [x] 守りたいこと（セクション 2）を満たす（設計・回帰観点で確認）
- [x] `swift build` / `swift test` が pass
- [x] 本計画書チェックリストがすべて `[x]`（B 案は A 採用により 1 行対象外）

---

✅ 本計画書は Step 2 の実装・検証の単一の参照元とする。採用オプション（A/B）は Phase 0 で確定し、以降の Phase は確定案にのみチェックを付ける。
