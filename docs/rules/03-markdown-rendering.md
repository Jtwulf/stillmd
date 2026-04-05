# Markdown 描画ルール

## 対応範囲

- stillmd の MVP は GitHub Flavored Markdown を対象にする
- 表、タスクリスト、取り消し線、オートリンク、 fenced code block を正しく扱う
- Mermaid の fenced code block は本文中で図として描画する
- LaTeX とその他の拡張プラグイン構文は初期スコープ外とする

## 描画方針

- Markdown は HTML 化して描画する
- コードブロックは syntax highlighting を行う
- 相対パスの画像とリンクは Markdown ファイルの親ディレクトリ基準で解決する
- `http:` / `https:` の外部リンクはシステムブラウザで開く

## セキュリティと制限

- ローカル viewer であっても、スクリプト実行や危険な HTML は安易に許可しない
- `javascript:` など危険な遷移は明示的に拒否する
- HTML の扱いを緩める場合は安全性、目的、体験上の必要性を説明できること

## 品質観点

- 長い Markdown でも再描画が極端に重くならないこと
- 再読み込み時にスクロール位置ができるだけ維持されること
- light / dark どちらでもコードブロック、表、引用の可読性が保たれること
