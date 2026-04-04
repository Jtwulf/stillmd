# 構成・責務分離

## 現在の主要構成

- `stillmd/App/`: App entry point
- `stillmd/Views/`: 画面表示、SwiftUI / WKWebView との接続
- `stillmd/ViewModels/`: 表示状態と読み込み状態
- `stillmd/Services/`: ファイル監視、リソース読み込み、バリデーションなどの補助責務
- `stillmd/Resources/`: CSS、JS ライブラリ、静的リソース
- `stillmdTests/`: テスト

## 責務分離の原則

- `App`: ウィンドウやアプリケーションレベルの入口だけを扱う
- `Views`: レンダリングと UI イベントの橋渡しを担う
- `ViewModels`: 画面状態、ファイルの読み込み結果、エラー状態を持つ
- `Services`: 再利用可能な補助ロジックを担う
- `Resources`: 見た目と描画ライブラリの静的資産を置く

## 実装時の判断基準

- View にロジックが増えすぎる場合は ViewModel / Service へ逃がす
- ViewModel に UI 固有の詳細が増えすぎる場合は View へ戻す
- 新しい責務が既存 Service に自然に入らないなら、新しい Service を作る
- デザイン思想の変更はコードだけでなく `DESIGN.md` や `docs/rules/` の更新要否も確認する

## 避けるべきこと

- 1 つの View に状態、描画、ファイル処理、外部連携を詰め込むこと
- UI の都合でアーキテクチャを不必要に複雑化すること
- 一時的な都合で Settings やメニュー構造を増やすこと

