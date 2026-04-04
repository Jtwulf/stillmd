# stillmd プロジェクトルール

本 repo は `AGENTS.md` を共通入口とし、`DESIGN.md` をデザイン憲法、`docs/rules/` を実装ルールの正本とする。`AGENTS.md` 自体は短く保ち、詳細は各ドキュメントへ分離する。

## エージェント向けルール（必須）

このプロジェクトのルールファイルを読み込んだ場合、作業開始時に以下を**必ず**応答に含めてください：

- 読み込んだファイルごとに `"[読了] ファイルパス"` と表示する
- 例: `"[読了] AGENTS.md"` `"[読了] DESIGN.md"` `"[読了] docs/rules/00-overview.md"`

## 最重要原則

- stillmd は **preview-only** の Markdown viewer であり、エディタ化しない
- 価値の優先順位は **ミニマルさ > 静けさ > 美しさ**
- UI は本文の可読性を最優先し、本文より強い存在感を持つ装飾を置かない
- 軽量性を常に守る。起動速度、メモリ、長文耐性、アプリサイズを悪化させる変更は慎重に扱う
- Apple の設計感覚は参照してよいが、模倣ではなく静かな実用性を優先する

## 禁止事項（要約）

- 不要なサイドバー、常設ツールバー、本文外の補助 UI を安易に追加しない
- 過剰なアニメーション、視線を奪う演出、ブランド表現のためだけの装飾を入れない
- 設定項目を増殖させない。設定は必要最小限に留める
- `AGENTS.md` や `DESIGN.md` に詳細仕様を積み上げすぎない

## 参照すべきドキュメント

| 作業内容 | 参照ファイル |
|----------|---------------|
| 作業開始時（必須） | @docs/rules/00-overview.md |
| UI / 見た目 / 体験設計 | @DESIGN.md |
| 構成・責務分離 | @docs/rules/01-architecture.md |
| UI 実装ルール | @docs/rules/02-ui-implementation.md |
| Markdown 描画 | @docs/rules/03-markdown-rendering.md |
| 軽量性・性能 | @docs/rules/04-performance.md |
| テスト・確認 | @docs/rules/05-testing.md |
| 文書運用 | @docs/rules/06-doc-governance.md |

## ドキュメント構成

- `AGENTS.md`: repo の入口。最重要原則と参照先だけを書く
- `DESIGN.md`: デザイン憲法。stillmd が何を美しいとみなすかを定義する
- `docs/rules/`: 実装ルールの正本
- `docs/plans/`: 実装計画書置き場

