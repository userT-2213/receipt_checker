# スマート支出管理アプリ (Smart Expense Manager)

大学3年生のPBL（課題解決型学習）として開発する、レシート画像解析機能付きの支出管理アプリケーションです。
手動での支出登録に加え、OpenCVとOCRを組み合わせたレシート解析補助機能を備え、最終的な支出データをCSVファイルで永続化・可視化します。

## 概要
本アプリは、「レシート入力の手間を減らす」ことと「正確なデータ管理」を両立する支出管理システムです。
OCRによる自動解析は100%の精度を目指すのではなく、**「AI/アルゴリズムが下書き（Draft）を作り、人間が確認・修正して確定（Confirm）する」**というアプローチ（Human-in-the-Loop）を採用し、ユーザーがストレスなく、かつ正確に家計簿をつけられる環境を提供します。

---

## 機能要件
1. **支出の手動登録機能**
   * 日付、店舗名、品名、金額、カテゴリをユーザーが直接入力して登録できること。
2. **レシート画像解析補助機能**
   * アップロードされたレシート画像をOpenCVで前処理し、OCRエンジンで文字を抽出して自動で入力フォームに下書き（補完）すること。
3. **データ検証とエラー表示**
   * 必須項目の未入力や、金額への文字入力などの不正なユーザー入力に対して、適切なエラーメッセージを表示すること。
4. **CSV永続化・履歴管理機能**
   * 確定した支出データをローカルのCSVファイルに追記・保存できること。また、保存された履歴一覧からデータを削除できること。
5. **ダッシュボード（集計・可視化）機能**
   * 期間別（月別など）の支出を集計し、カテゴリごとの割合を円グラフで可視化表示できること。

---

## サブ機能一覧
* **UI（ユーザーインターフェース）部**
  * 入力フォーム（手動入力・下書き修正用）
  * 画像アップロードコンポーネント
  * 履歴一覧データテーブル（削除ボタン付き）
  * 期間選択フィルター
  * 統計情報コンポーネント（総支出表示、Streamlitベースの円グラフ）
* **レシート解析部**
  * 画像前処理（グレースケール化、二値化などによるOCR精度向上）
  * 文字列パースアルゴリズム（OCRテキストから日付・金額・店名を特定する処理）
* **データ管理部**
  * CSV書き込み（バリデーション通過データの追記）
  * CSV読み込み（集計および履歴一覧表示用）
  * CSV行削除（物理削除対応）

---

## 作らないもの（スコープ外）
本プロジェクトの期間内では、以下の機能は実装対象外（スコープ外）とします。
* **ユーザー認証・アカウント管理機能**（ローカル環境での単一ユーザー利用を前提とするため、ログイン画面やマルチユーザー対応は行わない）
* **クラウドデータベース（RDB/NoSQL）の構築**（すべてのデータ管理はローカルのCSVファイルで行う）
* **高精度な汎用レシート解析**（あらゆるレシートへの対応は目指さず、特定のフォーマットや、一定の明瞭さを持つ画像にターゲットを限定する）
* **複数資産（口座・クレジットカード）の連携・管理**（現金や一括の支出管理のみに特化する）

---

## 設計図（Mermaid）

### ユースケース図
```mermaid
flowchart LR
    %% アクターの定義
    subgraph Actor [ ]
        style Actor fill:none,stroke:none
        User(((ユーザー)))
    end

    %% ユースケース（機能）の定義
    subgraph App [支出管理アプリ]
        %% メインユースケース
        UC1([支出を手動登録する])
        UC2([レシート画像を読み込む])
        UC3([期間別支出を集計する])
        UC4([円グラフで可視化する])
        
        %% 拡張・包含されるユースケース
        UC2_1([解析結果を手動修正する])
        UC_CSV_W([CSVファイルに書き込む])
        UC_CSV_R([CSVファイルを読み込む])
    end

    %% アクターからの直接的なアプローチ
    User --> UC1
    User --> UC2
    User --> UC3

    %% ユースケース間の関係（include / extend）
    
    %% レシート読み込みから手動修正への拡張 (extend)
    UC2 -. "«extend»" .-> UC2_1
    
    %% データの保存（手動登録・レシート確定はCSV書き込みを包含する）
    UC1 -. "«include»" .-> UC_CSV_W
    UC2_1 -. "«include»" .-> UC_CSV_W
    
    %% 集計・可視化（集計はCSV読み込みを包含し、円グラフ表示は集計に包含される）
    UC3 -. "«include»" .-> UC_CSV_R
    UC4 -. "«include»" .-> UC3

    %% スタイルの調整
    classDef actor fill:#f9f,stroke:#333,stroke-width:2px;
    classDef uc fill:#fff,stroke:#333,stroke-width:1px;
    class UC1,UC2,UC3,UC4,UC2_1,UC_CSV_W,UC_CSV_R uc;

```

### クラス図

```mermaid
classDiagram

class AppUI {
    +run()
    -renderInputForm()
    -renderDashboard()
}

class ExpenseController {
    +addExpense()
    +getAggregatedData()
}

class ReceiptProcessor {
    -openCVHandler
    -ocrEngine
    +extractExpenseFromImage()
}

class OpenCVHandler {
    +preprocessImage()
}

class OCREngine {
    +imageToText()
    +parseTextToDraft()
}

class ExpenseDraft {
    +date
    +store
    +item
    +amount
    +category
}

class ExpenseModel {
    +date
    +store
    +item
    +amount
    +category
}

class CSVDataManager {
    -filePath
    +save()
    +loadAll()
}

AppUI --> ExpenseController : uses
AppUI --> ReceiptProcessor : uses

ExpenseController --> CSVDataManager : manages
ExpenseController --> ExpenseModel : manages

ReceiptProcessor *-- OpenCVHandler
ReceiptProcessor *-- OCREngine

ReceiptProcessor ..> ExpenseDraft : creates
CSVDataManager ..> ExpenseModel : stores
```