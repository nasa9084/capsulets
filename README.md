# Capsulets

自分用の小さなアプリ（capsulet）をひとつにまとめたiOSアプリ。画面下部のタブで capsulet を切り替える。

| capsulet | 内容 |
| --- | --- |
| ごはんくじ | 食事の候補を複数選んで、ボタンを押すとその中から1つ選ばれる（ウィジェット付き） |

GitHub Actionsで未署名のIPAをビルドし、SideStoreで無料Apple IDで署名してiPhoneにインストールする。

## 構成

- `project.yml` — XcodeGenの定義（Actions上で `.xcodeproj` を生成する。プロジェクトファイルはコミットしない）
  - `Capsulets` — アプリ本体
  - `CapsuletsWidgets` — すべての capsulet のウィジェットを入れる拡張機能（App IDを増やさないように1つにまとめている）
- `Sources/App/` — タブの土台。`Capsulet.swift` の `CapsuletRegistry` に並べたものがタブになる
- `Sources/Capsulets/<名前>/` — 各 capsulet の画面
- `Shared/` — アプリとウィジェットで共有するコード
  - `AppGroup.swift` — 共有の保存先。capsulet ごとに `CapsuletStorage(prefix:)` でキーに接頭辞を付ける
  - `Shared/<名前>/` — 各 capsulet のデータ
- `Widget/` — ウィジェット。`CapsuletsWidgetBundle.swift` に各 capsulet のウィジェットを並べる
- `tools/draw_icon.py` — アイコン（`icon.png` と AppIcon）を生成する
- `.github/workflows/build.yml` — mainへのpushでビルドし、次を行う
  - `build-<番号>` リリースに `Capsulets.ipa` を添付
  - `source` リリースの `source.json`（SideStore用ソース）を最新ビルドで上書き

## capsulet の足し方

1. `Sources/Capsulets/<名前>/` に画面を作る
2. `Sources/App/Capsulet.swift` の `CapsuletRegistry.all` に追加する（タブ名・SF Symbolsのアイコン・画面）
3. 保存するデータがあれば `CapsuletStorage(prefix: "<名前>")` を使う（`@AppStorage` を使うときもキーに `<名前>.` を付ける）
4. ウィジェットを作るなら `Widget/<名前>/` に置き、`CapsuletsWidgetBundle` に追加する

## インストール

1. リポジトリは**public**のままにする（SideStoreが認証なしでリリースからダウンロードするため）
2. SideStoreの Sources → ＋ で次のURLを追加し、「Capsulets」をインストール
   `https://github.com/nasa9084/capsulets/releases/download/source/source.json`
3. 初回のダイアログでは「Keep App Extensions (Register App ID for Each Extension)」を選ぶ

## 更新

- mainにpushするとビルド番号が上がる。SideStoreの「My Apps」を下に引っぱって更新するとアップデートが表示される（タップで更新）

## 注意

- 無料Apple IDでは同時に有効なアプリが3つまで（SideStore自身を含む）。App IDは本体とウィジェットで2つ使う
