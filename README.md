# スマート支出管理アプリ (Smart Expense Manager)

大学3年生のPBL（課題解決型学習）として開発する、レシート画像解析機能付きの支出管理アプリケーションです。
手動での支出登録に加え、OpenCVとOCRを組み合わせたレシート解析補助機能を備え、最終的な支出データをCSVファイルで永続化・可視化します。

## 概要
本アプリは、「レシート入力のの手間を減らす」ことと「正確なデータ管理」を両立する支出管理システムです。
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

   ### ユースケース図
    classDiagram
    %% クラスの定義
    class AppUI {
        +run() void
        -renderInputForm() void
        -renderDashboard() void
    }

    class ExpenseController {
        +addExpense(date: String, store: String, item: String, amount: int, category: String) boolean
        +getAggregatedData(period: String) Map
    }

    class ReceiptProcessor {
        -openCVHandler: OpenCVHandler
        -ocrEngine: OCREngine
        +extractExpenseFromImage(imagePath: String) ExpenseDraft
    }

    class OpenCVHandler {
        +preprocessImage(imagePath: String) Object
    }

    class OCREngine {
        +imageToText(processedImage: Object) String
        +parseTextToDraft(text: String) ExpenseDraft
    }

    class ExpenseDraft {
        +date: String
        +store: String
        +item: String
        +amount: int
        +category: String
    }

    class ExpenseModel {
        +date: String
        +store: String
        +item: String
        +amount: int
        +category: String
    }

    class CSVDataManager {
        -filePath: String
        +save(expense: ExpenseModel) boolean
        +loadAll() List~ExpenseModel~
    }

    %% クラス間の関連・多重度
    AppUI "1" --> "1" ExpenseController : 処理を委譲
    AppUI "1" --> "1" ReceiptProcessor : 画像解析を依頼
    
    ExpenseController "1" --> "1" CSVDataManager : データの永続化
    ExpenseController "1" --> "*" ExpenseModel : 管理・集計
    
    %% コンポジション (ReceiptProcessorがHandlerやEngineを所有)
    ReceiptProcessor "1" *-- "1" OpenCVHandler : 内部で使用
    ReceiptProcessor "1" *-- "1" OCREngine : 内部で使用
    
    %% 依存/生成関係
    ReceiptProcessor ..> ExpenseDraft : 生成する >
    CSVDataManager ..> ExpenseModel : 生成/保存する >

    ###　シーケンス図

    sequenceDiagram
    autonumber
    actor User as ユーザー
    participant UI as 画面 (AppUI)
    participant Ctrl as コントローラ (ReceiptProcessor / ExpenseController)
    participant Model as モデル (CSVDataManager)

    %% 1. レシートのアップロードと解析
    User ->> UI: レシート画像をアップロード
    activate UI
    UI ->> Ctrl: extractExpenseFromImage(imagePath)
    activate Ctrl
    Note over Ctrl: OpenCVで画像前処理<br/>& OCRで文字抽出
    Ctrl -->> UI: ExpenseDraft (日付、店名、金額などの下書きデータ)
    deactivate Ctrl
    
    UI -->> User: 解析結果を入力フォームに下書き表示
    deactivate UI

    %% 2. 条件分岐：ユーザーによる確認と修正
    alt 解析結果が間違っている場合
        User ->> UI: 誤認識された箇所（金額や店名など）を修正
        activate UI
        UI -->> User: 修正内容を画面に反映
        deactivate UI
    else 解析結果が正しい場合
        Note over User: 修正なしでそのまま進む
    end

    %% 3. カテゴリ選択と確定・保存
    User ->> UI: カテゴリ（食費など）を選択し、「確定ボタン」を押下
    activate UI
    UI ->> Ctrl: addExpense(date, store, item, amount, category)
    activate Ctrl
    
    Ctrl ->> Model: save(ExpenseModel)
    activate Model
    Note over Model: CSVファイルへ<br/>新データを追記(Append)
    Model -->> Ctrl: 保存成功 (true)
    deactivate Model

    Ctrl -->> UI: 登録完了通知
    deactivate Ctrl
    UI -->> User: 「登録が完了しました」と画面に表示
    deactivate UI

    ###　状態遷移図

    stateDiagram-v2
    %% 初期状態
    [*] --> 生成中 : アプリで「入力」または「画像読込」を開始

    %% 状態の定義
    state 生成中 {
        [*] --> 空の状態 : 新規入力ボタン押下
        [*] --> 画像解析中 : レシート画像アップロード
        
        画像解析中 --> 解析完了 : OpenCV+OCR 処理完了
        空の状態 --> 手動入力中 : ユーザーが文字を入力
    }

    %% メインの状態遷移
    生成中 --> 未確定状態 (Draft) : 画面に入力フォーム（下書き）が表示される
    
    state 未確定状態 (Draft) {
        [*] --> 確認待ち
        確認待ち --> 修正中 : 誤認識・入力ミスを発見 [トリガー: ユーザーの編集変更]
        修正中 --> 確認待ち : 修正完了
    }

    未確定状態 (Draft) --> 確定状態 (Confirmed) : 「確定」ボタンを押下 [トリガー: 保存イベント発生]
    未確定状態 (Draft) --> 破棄状態 : 「キャンセル」または別の画像を選択

    確定状態 (Confirmed) --> 保存完了状態 (Saved) : CSVデータマネージャーが動作
    
    state 保存完了状態 (Saved) {
        [*] --> CSV格納済
        CSV格納済 --> 削除済 : 履歴一覧から削除 [トリガー: 削除ボタン押下]
    }

    %% 終了状態
    破棄状態 --> [*]
    保存完了状態 (Saved) --> [*] : アプリ終了、または次の入力へ
    削除済 --> [*] : CSVファイルから物理削除完了


#### クラス図
```mermaid
classDiagram
    %% クラスの定義
    class AppUI {
        +run() void
        -renderInputForm() void
        -renderDashboard() void
    }

    class ExpenseController {
        +addExpense(date: String, store: String, item: String, amount: int, category: String) boolean
        +getAggregatedData(period: String) Map
    }

    class ReceiptProcessor {
        -openCVHandler: OpenCVHandler
        -ocrEngine: OCREngine
        +extractExpenseFromImage(imagePath: String) ExpenseDraft
    }

    class OpenCVHandler {
        +preprocessImage(imagePath: String) Object
    }

    class OCREngine {
        +imageToText(processedImage: Object) String
        +parseTextToDraft(text: String) ExpenseDraft
    }

    class ExpenseDraft {
        +date: String
        +store: String
        +item: String
        +amount: int
        +category: String
    }

    class ExpenseModel {
        +date: String
        +store: String
        +item: String
        +amount: int
        +category: String
    }

    class CSVDataManager {
        -filePath: String
        +save(expense: ExpenseModel) boolean
        +loadAll() List~ExpenseModel~
    }

    %% クラス間の関連・多重度
    AppUI "1" --> "1" ExpenseController : 処理を委譲
    AppUI "1" --> "1" ReceiptProcessor : 画像解析を依頼
    
    ExpenseController "1" --> "1" CSVDataManager : データの永続化
    ExpenseController "1" --> "*" ExpenseModel : 管理・集計
    
    %% コンポジション (ReceiptProcessorがHandlerやEngineを所有)
    ReceiptProcessor "1" *-- "1" OpenCVHandler : 内部で使用
    ReceiptProcessor "1" *-- "1" OCREngine : 内部で使用
    
    %% 依存/生成関係
    ReceiptProcessor ..> ExpenseDraft : 生成する >
    CSVDataManager ..> ExpenseModel : 生成/保存する >

    ### シーケンス図
    sequenceDiagram
    autonumber
    actor User as ユーザー
    participant UI as 画面 (AppUI)
    participant Ctrl as コントローラ (ReceiptProcessor / ExpenseController)
    participant Model as モデル (CSVDataManager)

    %% 1. レシートのアップロードと解析
    User ->> UI: レシート画像をアップロード
    activate UI
    UI ->> Ctrl: extractExpenseFromImage(imagePath)
    activate Ctrl
    Note over Ctrl: OpenCVで画像前処理<br/>& OCRで文字抽出
    Ctrl -->> UI: ExpenseDraft (日付、店名、金額などの下書きデータ)
    deactivate Ctrl
    
    UI -->> User: 解析結果を入力フォームに下書き表示
    deactivate UI

    %% 2. 条件分岐：ユーザーによる確認と修正
    alt 解析結果が間違っている場合
        User ->> UI: 誤認識された箇所（金額や店名など）を修正
        activate UI
        UI -->> User: 修正内容を画面に反映
        deactivate UI
    else 解析結果が正しい場合
        Note over User: 修正なしでそのまま進む
    end

    %% 3. カテゴリ選択と確定・保存
    User ->> UI: カテゴリ（食費など）を選択し、「確定ボタン」を押下
    activate UI
    UI ->> Ctrl: addExpense(date, store, item, amount, category)
    activate Ctrl
    
    Ctrl ->> Model: save(ExpenseModel)
    activate Model
    Note over Model: CSVファイルへ<br/>新データを追記(Append)
    Model -->> Ctrl: 保存成功 (true)
    deactivate Model

    Ctrl -->> UI: 登録完了通知
    deactivate Ctrl
    UI -->> User: 「登録が完了しました」と画面に表示
    deactivate UI

    ### 状態遷移図
stateDiagram-v2
    %% 初期状態
    [*] --> 生成中 : アプリで「入力」または「画像読込」を開始

    %% 状態の定義
    state 生成中 {
        [*] --> 空の状態 : 新規入力ボタン押下
        [*] --> 画像解析中 : レシート画像アップロード
        
        画像解析中 --> 解析完了 : OpenCV+OCR 処理完了
        空の状態 --> 手動入力中 : ユーザーが文字を入力
    }

    %% メインの状態遷移
    生成中 --> 未確定状態 (Draft) : 画面に入力フォーム（下書き）が表示される
    
    state 未確定状態 (Draft) {
        [*] --> 確認待ち
        確認待ち --> 修正中 : 誤認識・入力ミスを発見 [トリガー: ユーザーの編集変更]
        修正中 --> 確認待ち : 修正完了
    }

    未確定状態 (Draft) --> 確定状態 (Confirmed) : 「確定」ボタンを押下 [トリガー: 保存イベント発生]
    未確定状態 (Draft) --> 破棄状態 : 「キャンセル」または別の画像を選択

    確定状態 (Confirmed) --> 保存完了状態 (Saved) : CSVデータマネージャーが動作
    
    state 保存完了状態 (Saved) {
        [*] --> CSV格納済
        CSV格納済 --> 削除済 : 履歴一覧から削除 [トリガー: 削除ボタン押下]
    }

    %% 終了状態
    破棄状態 --> [*]
    保存完了状態 (Saved) --> [*] : アプリ終了、または次の入力へ
    削除済 --> [*] : CSVファイルから物理削除完了