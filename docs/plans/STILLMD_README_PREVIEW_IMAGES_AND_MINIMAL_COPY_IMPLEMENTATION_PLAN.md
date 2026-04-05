# stillmd README プレビュー画像導入 / 最小構成推敲 実装計画書

## 0. この計画書の位置づけ

- 対象: `stillmd`
- 主題: 公開 README に stillmd のプレビュー画像を追加し、文面を stillmd の思想に合わせて最小限まで推敲する
- 本書は **Step 2 実行用の focused plan** であり、実装そのものは含まない
- 正本の思想は `AGENTS.md` / `DESIGN.md` / `docs/rules/00-overview.md` / `docs/rules/06-doc-governance.md` に置く
- README は公開向けの英語文書として保ち、内部思想や運用ルールを新たに README 側へ増やさない

## 1. 背景とキャッチアップ結果

### 1.1 ユーザー要望

- stillmd の一般公開に向けて、README に preview image を表示したい
- `assets/example-image` にある dark / light の 2 パターンを使いたい
- 画像を README にいい感じに配置し、初見ユーザーがアプリの雰囲気を掴めるようにしたい
- それに合わせて README を stillmd の哲学思想に合わせて推敲したい
- できるだけ最小限の記述に寄せたい

### 1.2 現状把握

- [README.md](../../README.md) は既に簡潔で、アイコン、短い導入文、機能、非ゴール、システム要件、Install、License で構成されている
- [assets/example-image/stillmd-image-dark.png](../../assets/example-image/stillmd-image-dark.png) と [assets/example-image/stillmd-image-light.png](../../assets/example-image/stillmd-image-light.png) が既に存在する
- `AGENTS.md` と `DESIGN.md` は stillmd の核を `preview-only`、`ミニマル`、`静けさ`、`本文が主役` と定義している
- `docs/rules/06-doc-governance.md` により、README は公開向け英語文書であり、内部 docs の役割と混ぜない方針が明示されている

### 1.3 既存計画との関係

- 既存の `README` 圧縮方針は `_backups/stillmd-main-20260405-004336/docs/plans/STILLMD_README_AND_REPO_TRIM_IMPLEMENTATION_PLAN.md` に痕跡がある
- ただし今回のスコープは repo 全体の trim ではなく、README の公開体験と preview image の導入に絞る
- `.DS_Store` や重複計画書の整理は、今回の主題とは分けて扱う

## 2. 目的と非ゴール

### 2.1 目的

- README の冒頭で stillmd の価値が一目で伝わるようにする
- preview image を 1 つの静かな導線として配置し、アプリの雰囲気を伝える
- dark / light の 2 パターンを、README 上で自然に切り替わる形で見せる
- README の文量を削り、重複説明をなくす
- stillmd の哲学に合う断定的で短い文体に寄せる

### 2.2 非ゴール

- アプリ機能の追加
- `DESIGN.md` の改稿
- README を詳細な仕様書や運用手順書に変えること
- preview image を複数枚並べて情報量を増やすこと
- repo 整理や不要ファイル削除を同時に進めること

## 3. 採用方針

### 3.1 画像の扱い

- README には画像ギャラリーを作らず、単一の preview slot を置く
- dark / light の 2 枚は、`<picture>` を使ってテーマに応じて切り替える
- `light` を fallback にし、`dark` は `prefers-color-scheme: dark` に合わせる
- 画像は `assets/example-image/` の既存ファイルをそのまま使う
- 画像の前後に過剰な説明文は置かない

### 3.2 README の文章方針

- 導入文は 1 〜 2 文に圧縮する
- `What it does` と `What it is not` は、必要最小限の箇条書きに留める
- 重複する説明は削る
- `System Requirements` は独立節として残すか、Install 節へ統合するかを Step 2 で最終判断する
- 公開 README らしく、内部設計の説明を増やしすぎない

### 3.3 レイアウト方針

- アイコンは冒頭に残す
- その直後に短い value proposition を置く
- その下に preview image を置く
- 画像のあとに最小限の本文説明を置く
- Install と License は残す

## 4. 対象ファイル

- `README.md`
- 必要な場合のみ `assets/example-image/stillmd-image-dark.png` と `assets/example-image/stillmd-image-light.png` を参照する

## 5. Phase 分割とチェックリスト

### Phase 1: README の最終構成を固定する

- [ ] README の役割を「公開向けの短い入口」に固定する
- [ ] 残す節を `Intro` / `Preview` / `What it does` / `What it is not` / `Install` / `License` 程度に絞る
- [ ] `System Requirements` を独立節として残すか、Install 節へ統合するかを確定する
- [ ] preview image は 1 枚の表示枠にまとめる方針で確定する
- [ ] README に内部 docs の説明を増やさない方針を固定する
- [ ] `AGENTS.md` / `DESIGN.md` の思想と矛盾しないことを確認する

### Phase 2: preview image の配置方針を実装に落とす

- [ ] `picture` ベースの記述で dark / light を切り替える
- [ ] 画像の参照先が `assets/example-image/stillmd-image-dark.png` と `assets/example-image/stillmd-image-light.png` であることを確認する
- [ ] 画像の alt 文言を stillmd の雰囲気に合う簡潔な表現にする
- [ ] 画像の前後に不要なキャプションや注釈を置かない
- [ ] 画像が README の視線の中心になるよう、導入文の直後に配置する
- [ ] 画像を複数枚並べて説明過多になっていないことを確認する

### Phase 3: README の文面を stillmd の思想に合わせて圧縮する

- [ ] 導入文を短い断定文へ再構成する
- [ ] `What it does` を必要最小限の事実列挙にする
- [ ] `What it is not` を 3 行前後に収める
- [ ] 重複する意味の文を削除する
- [ ] Install 節は導線として必要な情報だけ残す
- [ ] License 節と GitHub Releases 導線を壊さない
- [ ] README 全体の行数が「静かな公開入口」として妥当な範囲に収まる

### Phase 4: 確認

- [ ] README の Markdown と HTML が崩れていない
- [ ] dark / light のどちらでも画像導線が成立する
- [ ] README の導入だけで stillmd の雰囲気が伝わる
- [ ] 画像と文章の配置が stillmd らしく静かである
- [ ] `swift build` が成功する
- [ ] `swift test` が成功する
- [ ] 不要なファイル変更が混ざっていない

## 6. 完了条件

- [ ] README に stillmd の preview image が 1 つの静かな導線として配置されている
- [ ] dark / light の 2 パターンが適切に切り替わる
- [ ] README が stillmd の哲学に沿って最小限まで圧縮されている
- [ ] 重複説明や説明過多が解消されている
- [ ] `swift build` / `swift test` が通る

