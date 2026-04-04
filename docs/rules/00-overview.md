# stillmd 概要・必須ルール

## 読了ルール（必須）

このプロジェクトのルールファイルを読み込んだ場合、作業開始時に以下を**必ず**応答に含めてください：

- 読み込んだファイルごとに `"[読了] ファイルパス"` と表示する
- 例: `"[読了] docs/rules/00-overview.md"`

## プロダクトの定義

stillmd は、macOS 向けの軽量な preview-only Markdown viewer である。
編集機能、情報密度の高い補助 UI、多機能ワークスペース化は目的に含めない。

## 優先順位

実装判断は以下の優先順位に従う。

1. ミニマルさ
2. 静けさ
3. 美しさ
4. 可読性
5. 軽量性

上位を壊して下位を満たす変更は採用しない。

## 文書体系

- `AGENTS.md`: 入口
- `DESIGN.md`: デザイン憲法
- `docs/rules/`: 実装ルール
- `docs/plans/`: 実装計画書

## 共通チェック

- preview-only の境界を守っているか
- 不要な常設 UI を増やしていないか
- light / dark の両方で体験が破綻しないか
- 起動速度、メモリ、長文耐性、アプリサイズを悪化させていないか
- README と内部 docs の役割を混ぜていないか

## 参照

- デザイン: @DESIGN.md
- 構成: @docs/rules/01-architecture.md
- UI 実装: @docs/rules/02-ui-implementation.md
- Markdown 描画: @docs/rules/03-markdown-rendering.md
- 性能: @docs/rules/04-performance.md
- テスト: @docs/rules/05-testing.md
- 文書運用: @docs/rules/06-doc-governance.md

