import 'dart:convert';
import 'dart:async'; // Completer用
import 'package:flutter/foundation.dart'; // kIsWebの判定用
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// ★これに差し替え：Webの時だけ実際の処理を、それ以外はスタブを読み込む
import 'web_ocr_stub.dart' if (dart.library.js) 'web_ocr.dart' as web_ocr;
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartReceiptCheckerApp());
}

class SmartReceiptCheckerApp extends StatelessWidget {
  const SmartReceiptCheckerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'レシートチェック＆支出管理アプリ',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF0F2F6),
      ),
      // --- 日本語化のための設定を追加 ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      // --------------------------------
      home: const MainTabScreen(),
      locale: const Locale('ja', 'JP'),
    );
  }
}

// --- モデル & データ構造の定義 ---

class ExpenseData {
  String date; // YYYY-MM-DD
  String store;
  String item;
  int amount;
  String category;

  ExpenseData({
    required this.date,
    required this.store,
    required this.item,
    required this.amount,
    required this.category,
  });

  Map<String, dynamic> toMap() {
    return {'date': date, 'store': store, 'item': item, 'amount': amount, 'category': category};
  }

  factory ExpenseData.fromMap(Map<String, dynamic> map) {
    return ExpenseData(
      date: map['date'] ?? '',
      store: map['store'] ?? '',
      item: map['item'] ?? '',
      amount: map['amount'] ?? 0,
      category: map['category'] ?? 'その他',
    );
  }
}

// --- Web/モバイル両対応ストレージマネージャー（SharedPreferencesへ移行） ---

class LocalDataManager {
  static const String _storageKey = 'expenses_data_list';

  Future<List<ExpenseData>> loadAllExpenses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_storageKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((e) => ExpenseData.fromMap(e)).toList();
    } catch (e) {
      debugPrint("データ読み込みエラー: $e");
      return [];
    }
  }

  Future<bool> saveExpense(ExpenseData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await loadAllExpenses();
      list.add(data);
      final String encoded = jsonEncode(list.map((e) => e.toMap()).toList());
      await prefs.setString(_storageKey, encoded);
      return true;
    } catch (e) {
      debugPrint("データ保存エラー: $e");
      return false;
    }
  }

  Future<bool> deleteExpensesByIndices(List<int> indicesToDelete) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await loadAllExpenses();
      indicesToDelete.sort((a, b) => b.compareTo(a));
      for (var index in indicesToDelete) {
        if (index >= 0 && index < list.length) {
          list.removeAt(index);
        }
      }
      final String encoded = jsonEncode(list.map((e) => e.toMap()).toList());
      await prefs.setString(_storageKey, encoded);
      return true;
    } catch (e) {
      debugPrint("データ削除エラー: $e");
      return false;
    }
  }
}

// --- メインタブ画面 ---

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({Key? key}) : super(key: key);

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final LocalDataManager _dataManager = LocalDataManager();
  List<ExpenseData> _allExpenses = [];

  final List<String> _categories = [
    "食費", "日用品", "交通費", "交際費", "娯楽・趣味", "教育", 
    "水道・光熱費", "家賃", "保険", "通信費", "美容・衣服", "医療・健康", "その他"
  ];
  
  final Map<String, Color> _categoryColorMap = {
    "食費": const Color(0xFFFF9999), "日用品": const Color(0xFFFFCC99),
    "交通費": const Color(0xFFFFFF99), "交際費": const Color(0xFFCCFF99),
    "娯楽・趣味": const Color(0xFF99FF99), "教育": const Color(0xFFB3F0FF),
    "水道・光熱費": const Color(0xA6C8FF00), "家賃": const Color(0xFFD9B3FF),
    "保険": const Color(0xFFFFCCE6), "通信費": const Color(0xFFFFA6FF),
    "美容・衣服": const Color(0xFF7CA48D), "医療・健康": const Color(0xFFD3D3D3),
    "その他": const Color(0xFF85DFB3)
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshData();
  }

  Future<void> _refreshData() async {
    final data = await _dataManager.loadAllExpenses();
    setState(() {
      _allExpenses = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('レシートチェック&支出管理', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.teal,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.move_to_inbox), text: '📥 レシート登録・入力'),
            Tab(icon: Icon(Icons.bar_chart), text: '📊 支出集計ダッシュボード'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          InputTab(
            dataManager: _dataManager, 
            categories: _categories, 
            allExpenses: _allExpenses,
            onDataChanged: _refreshData,
            categoryColorMap: _categoryColorMap,
          ),
          DashboardTab(
            allExpenses: _allExpenses, 
            categories: _categories,
            categoryColorMap: _categoryColorMap,
          ),
        ],
      ),
    );
  }
}


// ==========================================
// タブ1: レシート登録・入力
// ==========================================
class InputTab extends StatefulWidget {
  final LocalDataManager dataManager;
  final List<String> categories;
  final List<ExpenseData> allExpenses;
  final VoidCallback onDataChanged;
  final Map<String, Color> categoryColorMap;

  const InputTab({
    Key? key,
    required this.dataManager,
    required this.categories,
    required this.allExpenses,
    required this.onDataChanged,
    required this.categoryColorMap,
  }) : super(key: key);

  @override
  State<InputTab> createState() => _InputTabState();
}

class _InputTabState extends State<InputTab> {
  Uint8List? _webImageBytes; // Web/モバイル共通のプレビュー対応用バイトデータ
  final _picker = ImagePicker();
  bool _isProcessing = false;

  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController();
  final _storeController = TextEditingController();
  final _itemController = TextEditingController();
  final _amountController = TextEditingController();
  String _selectedCategory = "食費";

  String _sortTarget = "新しい順";
  String _sortOrder = "降順";
  bool _deleteMode = false;
  final List<int> _selectedIndicesForDelete = [];

  @override
  void initState() {
    super.initState();
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  // カレンダー表示処理の実装
  Future<void> _selectDate(BuildContext context) async {
    DateTime initialDate = DateTime.tryParse(_dateController.text) ?? DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

 Future<void> _processReceipt(XFile pickedFile) async {
    setState(() {
      _isProcessing = true;
    });

    String detectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    String detectedShop = "";
    int detectedPrice = 0;
    List<String> detectedItems = [];
    List<String> textLines = [];

    try {
      if (kIsWeb) {
        final rawResponse = await web_ocr.runTesseractWeb(pickedFile);
        if (rawResponse.startsWith('JS_ERROR') || rawResponse.startsWith('DART_ERROR')) {
          throw Exception(rawResponse);
        }
        textLines = rawResponse
            .split('[LINE]')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else {
        final inputImage = InputImage.fromFilePath(pickedFile.path);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);
        try {
          final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
          textLines = recognizedText.blocks.map((b) => b.text.trim()).toList();
        } finally {
          textRecognizer.close();
        }
      }

      // --- 1. 店名の抽出 ---
      String baseShopName = "";
      String branchName = "";
      int checkLimit = textLines.length > 7 ? 7 : textLines.length;
      
      for (int i = 0; i < checkLimit; i++) {
        String textClean = textLines[i].replaceAll(RegExp(r'\s+'), '');
        if (textClean.length <= 1) continue;
        if (RegExp(r'\d{4}[年\-/]|\d{1,2}[月\-/]').hasMatch(textClean)) continue;
        if (RegExp(r'TEL|tel|0\d{1,4}-\d{1,4}-\d{3,4}').hasMatch(textClean)) continue;
        if (RegExp(r'領収|レシート|登録|番号').hasMatch(textClean)) continue;
        if (RegExp(r'[xXメ*✕×]\d+|\d+円|[￥\\¥]').hasMatch(textClean)) continue;

        textClean = textClean.replaceAll("ナインイレナン", "ナインイレブン").replaceAll("ナインイレプン", "ナインイレブン").replaceAll("ナインイレプブン", "ナインイレブン");
        baseShopName = textClean;

        if (textClean.contains("店") && textClean.length > 3) {
          break;
        } else if (i + 1 < textLines.length) {
          String nextText = textLines[i + 1].replaceAll(RegExp(r'\s+'), '');
          if (nextText.contains("店") && !RegExp(r'\d+円|TEL').hasMatch(nextText)) {
            branchName = nextText;
          }
          break;
        }
      }

      if (baseShopName.isNotEmpty) {
        detectedShop = branchName.isNotEmpty && !baseShopName.contains(branchName)
            ? "$baseShopName$branchName"
            : baseShopName;
      }

      // --- 2. 品名・日付・金額の抽出 ---
      for (int i = 0; i < textLines.length; i++) {
        String originalLine = textLines[i];
        String cleanLine = originalLine.replaceAll(RegExp(r'\s+'), '');

        // 日付の抽出
        var dateMatch = RegExp(r'(\d{4})\s*[年\-/]\s*(\d{1,2})\s*[月\-/]\s*(\d{1,2})').firstMatch(originalLine);
        if (dateMatch != null) {
          int year = int.parse(dateMatch.group(1)!);
          int month = int.parse(dateMatch.group(2)!);
          int day = int.parse(dateMatch.group(3)!);
          detectedDate = "$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}";
          continue;
        }

        // 合計金額の抽出
        if (cleanLine.contains("計") || cleanLine.contains("合")) {
          var numbers = RegExp(r'\d+').allMatches(cleanLine).map((m) => m.group(0)!).toList();
          if (numbers.isNotEmpty) {
            detectedPrice = int.tryParse(numbers.last) ?? detectedPrice;
          }
          continue;
        }

        // 【修正】除外キーワードの判定を強化（お預りや店名ブレ、住所等のキーワードを追加）
        bool isExcludeKeyword = RegExp(r'計|釣|税|小計|割引|値引|領収|TEL|号|責|登録|単価|現|金|クレジット|会員|スキャン|預り|預リ|ナインイレ|千葉県|船橋市').hasMatch(cleanLine);
        bool isDateTimeOrPhone = RegExp(r'\d{2}:\d{2}|0\d{1,4}-\d{1,4}-\d{3,4}|\d{4}年').hasMatch(cleanLine);

        if (!isExcludeKeyword && !isDateTimeOrPhone) {
          String candidate = originalLine;

          // 数量や金額部分を前方一致でカット
          var itemMatch = RegExp(r'(.+?)(?=[xXメ*✕×]\d|[\d,]+円|[￥\\¥])').firstMatch(originalLine);
          if (itemMatch != null) {
            candidate = itemMatch.group(1)!.trim();
          }

          // 末尾に残ったノイズをトリミング
          candidate = candidate.replaceAll(RegExp(r'[\s_。、\.・=+\-xX✕×\d]+$'), '').trim();

          // 抽出した店名自体、または店名に含まれる文字列も完全に除外
          bool isShopName = detectedShop.isNotEmpty && (detectedShop.contains(candidate) || candidate.contains(detectedShop));

          if (candidate.length >= 2 && !isShopName && !candidate.contains("店")) {
            detectedItems.add(candidate);
          }
        }
      }

      if (detectedPrice == 0) {
        for (var line in textLines) {
          if (line.contains("合計") || line.contains("小計")) {
            String numOnly = line.replaceAll(RegExp(r'[^\d]'), '');
            if (numOnly.isNotEmpty) {
              detectedPrice = int.tryParse(numOnly) ?? detectedPrice;
              break;
            }
          }
        }
      }

      if (detectedShop.isEmpty && textLines.isNotEmpty) {
        detectedShop = textLines.first.replaceAll(RegExp(r'\s+'), '');
      }

      // 各フォームに入力値をセット
      setState(() {
        _dateController.text = detectedDate;
        _storeController.text = detectedShop.isEmpty ? "ナインイレブン日大前店" : detectedShop;
        _amountController.text = detectedPrice == 0 ? "" : detectedPrice.toString();
        _selectedCategory = "食費";
        
        if (detectedItems.isNotEmpty) {
          _itemController.text = detectedItems.join("\n");
        } else {
          _itemController.text = "商品名を検出できませんでした";
        }
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('解析エラー: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  List<MapEntry<int, ExpenseData>> _getProcessedHistory() {
    List<MapEntry<int, ExpenseData>> indexedList = [];
    for (int i = 0; i < widget.allExpenses.length; i++) {
      indexedList.add(MapEntry(i, widget.allExpenses[i]));
    }

    bool isAsc = (_sortOrder == "昇順");
    if (_sortTarget == "新しい順") {
      indexedList.sort((a, b) => isAsc ? a.key.compareTo(b.key) : b.key.compareTo(a.key));
    } else if (_sortTarget == "金額順") {
      indexedList.sort((a, b) => isAsc ? a.value.amount.compareTo(b.value.amount) : b.value.amount.compareTo(a.value.amount));
    } else if (_sortTarget == "日付順") {
      indexedList.sort((a, b) {
        int comp = a.value.date.compareTo(b.value.date);
        return isAsc ? comp : -comp;
      });
    }
    return indexedList;
  }

  @override
  Widget build(BuildContext context) {
    final historyData = _getProcessedHistory();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("1. レシート画像のアップロード", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await _picker.pickImage(source: ImageSource.gallery);
                    if (picked != null) {
                      final bytes = await picked.readAsBytes();
                      setState(() { _webImageBytes = bytes; });
                      _processReceipt(picked);
                    }
                  },
                  icon: const Icon(Icons.photo_library),
                  label: const Text("ギャラリーから選択"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await _picker.pickImage(source: ImageSource.camera);
                    if (picked != null) {
                      final bytes = await picked.readAsBytes();
                      setState(() { _webImageBytes = bytes; });
                      _processReceipt(picked);
                    }
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("カメラで撮影"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
          if (_isProcessing) ...[
            const SizedBox(height: 15),
            const LinearProgressIndicator(color: Colors.teal),
            const Center(child: Text("AI文字解析を実行中...", style: TextStyle(fontSize: 12, color: Colors.grey))),
          ],
          if (_webImageBytes != null) ...[
            const SizedBox(height: 10),
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Image.memory(_webImageBytes!, fit: BoxFit.contain),
            ),
          ],
          const SizedBox(height: 25),
          
          const Text("2. 支出情報の入力・確認", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 10),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _dateController,
                      readOnly: true, // 手入力を防ぎタップ選択に強制
                      onTap: () => _selectDate(context),
                      decoration: const InputDecoration(labelText: "日付 (YYYY-MM-DD)", suffixIcon: Icon(Icons.calendar_today)),
                      validator: (v) => (v == null || v.isEmpty) ? "日付を入力してください" : null,
                    ),
                    TextFormField(
                      controller: _storeController,
                      decoration: const InputDecoration(labelText: "店名"),
                      validator: (v) => (v == null || v.trim().isEmpty) ? "店名を入力してください" : null,
                    ),
                    TextFormField(
                      controller: _itemController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: "商品名（改行可）"),
                      validator: (v) => (v == null || v.trim().isEmpty) ? "商品名を入力してください" : null,
                    ),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "金額 (円)"),
                      validator: (v) {
                        if (v == null || int.tryParse(v) == null || int.parse(v) <= 0) return "正しい金額を入力してください";
                        return null;
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      items: widget.categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) { if (val != null) setState(() { _selectedCategory = val; }); },
                      decoration: const InputDecoration(labelText: "カテゴリ"),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            final data = ExpenseData(
                              date: _dateController.text,
                              store: _storeController.text.trim(),
                              item: _itemController.text.trim(),
                              amount: int.parse(_amountController.text),
                              category: _selectedCategory,
                            );
                            final success = await widget.dataManager.saveExpense(data);
                            if (success) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('データを保存しました！')));
                              _storeController.clear();
                              _itemController.clear();
                              _amountController.clear();
                              setState(() { _webImageBytes = null; });
                              widget.onDataChanged(); // 親のリスト状態を更新
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                        child: const Text("データを保存する", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 25),

          const Text("3. 登録データ履歴", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 10),
          if (widget.allExpenses.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: Text("データがありません。", style: TextStyle(color: Colors.grey))))
          else ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _sortTarget,
                    isExpanded: true,
                    items: ["新しい順", "金額順", "日付順"].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) { if (v != null) setState(() { _sortTarget = v; }); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _sortOrder,
                    isExpanded: true,
                    items: ["降順", "昇順"].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) { if (v != null) setState(() { _sortOrder = v; }); },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (!_deleteMode) {
                      setState(() { _deleteMode = true; _selectedIndicesForDelete.clear(); });
                    } else {
                      if (_selectedIndicesForDelete.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除する項目が選択されていません。'), backgroundColor: Colors.red));
                      } else {
                        final success = await widget.dataManager.deleteExpensesByIndices(_selectedIndicesForDelete);
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_selectedIndicesForDelete.length}件のデータを削除しました。')));
                          setState(() { _deleteMode = false; _selectedIndicesForDelete.clear(); });
                          widget.onDataChanged();
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: _deleteMode ? Colors.red : Colors.grey.shade700, foregroundColor: Colors.white),
                  child: Text(_deleteMode ? "🔴 削除" : "🗑 削除モード"),
                ),
                if (_deleteMode) ...[
                  const SizedBox(width: 4),
                  IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () { setState(() { _deleteMode = false; }); })
                ]
              ],
            ),
            if (_deleteMode)
              const Padding(
                padding: EdgeInsets.only(bottom: 8.0),
                child: Text("⚠️ 削除したい項目にチェックを入れ、「🔴 削除」を押してください。", style: TextStyle(color: Colors.red, fontSize: 11)),
              ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: historyData.length,
              itemBuilder: (context, idx) {
                final entry = historyData[idx];
                final originalIdx = entry.key;
                final expense = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: _deleteMode
                        ? Checkbox(
                            value: _selectedIndicesForDelete.contains(originalIdx),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedIndicesForDelete.add(originalIdx);
                                } else {
                                  _selectedIndicesForDelete.remove(originalIdx);
                                }
                              });
                            },
                          )
                        : Container(
                            width: 12, height: 12,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.categoryColorMap[expense.category] ?? Colors.teal),
                          ),
                    title: Text("${expense.store} (${expense.category})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text("${expense.date}\n${expense.item}", style: const TextStyle(fontSize: 12)),
                    trailing: Text("${NumberFormat('#,###').format(expense.amount)} 円", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          ]
        ],
      ),
    );
  }
}

// ==========================================
// タブ2: 支出集計ダッシュボード
// ==========================================
class DashboardTab extends StatefulWidget {
  final List<ExpenseData> allExpenses;
  final List<String> categories;
  final Map<String, Color> categoryColorMap;

  const DashboardTab({
    Key? key,
    required this.allExpenses,
    required this.categories,
    required this.categoryColorMap,
  }) : super(key: key);

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  String _syncScope = "週単位";
  int _syncYear = DateTime.now().year;
  int _syncMonth = DateTime.now().month;
  int _syncWeek = 1;

  String _pieScopeSelection = "月単位";

  @override
  void initState() {
    super.initState();
    _syncWeek = _getWeekNumber(DateTime.now());
  }

  int _getWeekNumber(DateTime dt) {
    // その月の1日を取得
    final firstDayOfMonth = DateTime(dt.year, dt.month, 1);
    
    // 1日の曜日 (1:月, ..., 6:土, 7:日) を日曜日始まり(0)〜土曜日(6)のオフセットに変換
    final firstDayOffset = firstDayOfMonth.weekday == 7 ? 0 : firstDayOfMonth.weekday;
    
    // (日付 + 1日のオフセット - 1) を 7 で割ることで、カレンダー上の行数（第何週）を算出
    return ((dt.day + firstDayOffset - 1) / 7).floor() + 1;
  }

  int _getDaysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  // 選択された月が最大で第何週まであるかを計算する
  int _getMaxWeeksInMonth(int year, int month) {
    // その月の最終日（例: 31日）を取得
    final lastDayOfMonth = DateTime(year, month + 1, 0);
    // 最終日が第何週に属するかをそのまま最大週数とする
    return _getWeekNumber(lastDayOfMonth);
  }

  // ★ 追加：前の月へ移動するロジック（年またぎ対応）
  void _previousMonth() {
    setState(() {
      if (_syncMonth == 1) {
        _syncMonth = 12;
        _syncYear--;
      } else {
        _syncMonth--;
      }
      // 月が変わったら安全のために週数を第1週にリセット
      _syncWeek = 1;
    });
  }

  // ★ 追加：次の月へ移動するロジック（年またぎ対応）
  void _nextMonth() {
    setState(() {
      if (_syncMonth == 12) {
        _syncMonth = 1;
        _syncYear++;
      } else {
        _syncMonth++;
      }
      // 月が変わったら安全のために週数を第1週にリセット
      _syncWeek = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allExpenses.isEmpty) {
      return const Center(child: Text("集計するデータがまだありません。"));
    }

    int totalAll = widget.allExpenses.fold(0, (sum, item) => sum + item.amount);
    
    List<ExpenseData> filteredExpenses = widget.allExpenses.where((item) {
      DateTime? dt = DateTime.tryParse(item.date);
      if (dt == null) return false;
      if (dt.year != _syncYear) return false;
      
      if (_syncScope == "年単位") return true;
      if (dt.month != _syncMonth) return false;
      
      if (_syncScope == "月単位") return true;
      return _getWeekNumber(dt) == _syncWeek;
    }).toList();

    int selectedPeriodAmount = filteredExpenses.fold(0, (sum, item) => sum + item.amount);
    
    int periodDays = 365;
    if (_syncScope == "週単位") periodDays = 7;
    else if (_syncScope == "月単位") periodDays = _getDaysInMonth(_syncYear, _syncMonth);
    else periodDays = ((_syncYear % 4 == 0 && _syncYear % 100 != 0) || _syncYear % 400 == 0) ? 366 : 365;

    int calculatedAverage = periodDays > 0 ? (selectedPeriodAmount / periodDays).round() : 0;

    List<ExpenseData> pieFilteredExpenses = widget.allExpenses.where((item) {
      DateTime? dt = DateTime.tryParse(item.date);
      if (dt == null) return false;
      if (_pieScopeSelection == "全期間") return true;
      if (dt.year != _syncYear) return false;
      if (_pieScopeSelection == "年単位") return true;
      return dt.month == _syncMonth;
    }).toList();

    Map<String, int> categorySums = {};
    for (var item in pieFilteredExpenses) {
      categorySums[item.category] = (categorySums[item.category] ?? 0) + item.amount;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("📊 期間別集計データ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 10),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // 1行目: ラジオボタン（画面からはみ出さないよう横スクロール可能に）
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ["週単位", "月単位", "年単位"].map((scope) {
                        return Row(
                          children: [
                            Radio<String>(
                              value: scope,
                              groupValue: _syncScope,
                              activeColor: Colors.teal,
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _syncScope = v;
                                    _pieScopeSelection = (v == "週単位" || v == "月単位") ? "月単位" : "年単位";
                                  });
                                }
                              },
                            ),
                            Text(scope, style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 2行目: 重複を削除し、「年・月・週」が1つずつ綺麗に並ぶドロップダウン
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _syncYear,
                          decoration: const InputDecoration(labelText: "年"),
                          items: List.generate(11, (i) => DateTime.now().year - 5 + i).map((y) => DropdownMenuItem(value: y, child: Text("$y年"))).toList(),
                          onChanged: (v) { if (v != null) setState(() { _syncYear = v; }); },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _syncMonth,
                          decoration: const InputDecoration(labelText: "月"),
                          items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text("$m月"))).toList(),
                          onChanged: _syncScope == "年単位" ? null : (v) { if (v != null) setState(() { _syncMonth = v; }); },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final maxWeeks = _getMaxWeeksInMonth(_syncYear, _syncMonth);
                            if (_syncWeek > maxWeeks) {
                              _syncWeek = 1;
                            }
                            return DropdownButtonFormField<int>(
                              value: _syncWeek,
                              decoration: const InputDecoration(labelText: "週"),
                              items: List.generate(maxWeeks, (i) => i + 1).map((w) => DropdownMenuItem(value: w, child: Text("第$w週"))).toList(),
                              onChanged: (_syncScope == "月単位" || _syncScope == "年単位") ? null : (v) { if (v != null) setState(() { _syncWeek = v; }); },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),

          // --- ここから：Builderで包んだ比較・集計とGridViewのブロック ---
          Builder(
            builder: (context) {
              int previousPeriodAmount = 0;

              if (_syncScope == "週単位") {
                int prevWeek = _syncWeek - 1;
                int prevMonth = _syncMonth;
                int prevYear = _syncYear;
                if (prevWeek < 1) {
                  prevMonth -= 1;
                  if (prevMonth < 1) {
                    prevMonth = 12;
                    prevYear -= 1;
                  }
                  prevWeek = _getMaxWeeksInMonth(prevYear, prevMonth);
                }
                
                final prevExpenses = widget.allExpenses.where((e) {
                  if (e.date.length < 10) return false;
                  final date = DateTime.tryParse(e.date);
                  if (date == null) return false;
                  return date.year == prevYear && date.month == prevMonth && _getWeekNumber(date) == prevWeek;
                });
                for (var e in prevExpenses) { previousPeriodAmount += (e.amount as num).toInt(); }

              } else if (_syncScope == "月単位") {
                int prevMonth = _syncMonth - 1;
                int prevYear = _syncYear;
                if (prevMonth < 1) {
                  prevMonth = 12;
                  prevYear -= 1;
                }
                final prefix = "$prevYear-${prevMonth.toString().padLeft(2, '0')}";
                final prevExpenses = widget.allExpenses.where((e) => e.date.startsWith(prefix));
                for (var e in prevExpenses) { previousPeriodAmount += (e.amount as num).toInt(); }

              } else if (_syncScope == "年単位") {
                final prefix = "${_syncYear - 1}-";
                final prevExpenses = widget.allExpenses.where((e) => e.date.startsWith(prefix));
                for (var e in prevExpenses) { previousPeriodAmount += (e.amount as num).toInt(); }
              }

              // 差額と％の計算（金額・％の順に修正）
              int diffAmount = selectedPeriodAmount - previousPeriodAmount;
              String compareValueText = "";
              
              if (previousPeriodAmount == 0) {
                String diffText = diffAmount >= 0 
                    ? "+${NumberFormat('#,###').format(diffAmount)}円" 
                    : "${NumberFormat('#,###').format(diffAmount)}円";
                compareValueText = diffAmount >= 0 ? "$diffText (+100.0%)" : "$diffText (0.0%)";
              } else {
                double percent = (diffAmount / previousPeriodAmount) * 100;
                String percentText = "";
                String diffText = "";
                
                if (diffAmount > 0) {
                  percentText = "+${percent.toStringAsFixed(1)}%";
                  diffText = "+${NumberFormat('#,###').format(diffAmount)}円";
                } else if (diffAmount < 0) {
                  percentText = "${percent.toStringAsFixed(1)}%";
                  diffText = "${NumberFormat('#,###').format(diffAmount)}円";
                } else {
                  percentText = "0.0%";
                  diffText = "0円";
                }
                
                // 金額を先、％をカッコ内に配置
                compareValueText = "$diffText ($percentText)";
              }

              String compareTitle = "⚖️ 前期比 (${_syncScope == '週単位' ? '先週' : _syncScope == '月単位' ? '先月' : '前年'}比)";

              // 画面に表示する GridView を return で返す
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  _buildMetricCard("📊 累計総支出額", "${NumberFormat('#,###').format(totalAll)} 円"),
                  Builder(
                    builder: (context) {
                      String label = "🧮 選択期間の支出";
                      if (_syncScope == "週単位") {
                        label = "🧮 $_syncYear年$_syncMonth月第$_syncWeek週の支出";
                      } else if (_syncScope == "月単位") {
                        label = "🧮 $_syncYear年$_syncMonth月の支出";
                      } else if (_syncScope == "年単位") {
                        label = "🧮 $_syncYear年の支出";
                      }
                      return _buildMetricCard(label, "${NumberFormat('#,###').format(selectedPeriodAmount)} 円");
                    },
                  ),
                  _buildMetricCard("📐 期間中の1日平均支出", "${NumberFormat('#,###').format(calculatedAverage)} 円"),
                  _buildMetricCard(compareTitle, compareValueText),
                ],
              );
            },
          ),
          // --- ここまで：BuilderとGridViewのブロック ---
          const SizedBox(height: 25),

          // --- カレンダーのヘッダーとプルダウン・矢印ボタン部分 ---
          Card(
            elevation: 0,
            color: Colors.teal.withOpacity(0.05),
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        String calendarTitle = "📅 支出カレンダー";
                        if (_syncScope == "週単位") {
                          calendarTitle = "📅 日付別の支出カレンダー ($_syncYear年$_syncMonth月 第$_syncWeek週)";
                        } else if (_syncScope == "月単位") {
                          calendarTitle = "📅 日付別の支出カレンダー ($_syncYear年$_syncMonth月分)";
                        } else if (_syncScope == "年単位") {
                          calendarTitle = "📅 日付別の支出カレンダー ($_syncYear年分)";
                        }
                        return Text(
                          calendarTitle,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal),
                        );
                      },
                    ),
                  ),
                  // ★ 修正：月の横に左右の切り替え矢印を配置したコントロール群
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 90,
                        child: DropdownButtonFormField<int>(
                          value: _syncYear,
                          decoration: const InputDecoration(labelText: "年", contentPadding: EdgeInsets.symmetric(vertical: 4)),
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          items: List.generate(11, (i) => DateTime.now().year - 5 + i).map((y) => DropdownMenuItem(value: y, child: Text("$y年"))).toList(),
                          onChanged: (v) { if (v != null) setState(() { _syncYear = v; }); },
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 左矢印ボタン
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.arrow_back_ios, size: 16, color: Colors.teal),
                        onPressed: _previousMonth,
                        tooltip: "前の月へ",
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 75,
                        child: DropdownButtonFormField<int>(
                          value: _syncMonth,
                          decoration: const InputDecoration(labelText: "月", contentPadding: EdgeInsets.symmetric(vertical: 4)),
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          items: List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(value: m, child: Text("$m月"))).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _syncMonth = v;
                                if (_syncScope == "年単位") {
                                  _syncScope = "月単位";
                                  _pieScopeSelection = "月単位";
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 右矢印ボタン
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.teal),
                        onPressed: _nextMonth,
                        tooltip: "次の月へ",
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          _buildCalendarGrid(), // カレンダー本体の呼び出し
          const SizedBox(height: 25),

          const Text("🍕 カテゴリ割合", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            // 「週単位」をリストの先頭に追加
            children: ["週単位", "月単位", "年単位", "全期間"].map((pScope) {
              return Row(
                children: [
                  Radio<String>(
                    value: pScope, 
                    groupValue: _pieScopeSelection, 
                    activeColor: Colors.teal,
                    onChanged: (v) { 
                      if (v != null) {
                        setState(() { 
                          _pieScopeSelection = v; 
                          
                          // --- 期間別集計・支出合計との連動処理 ---
                          if (v == "週単位") {
                            _syncScope = "週単位";
                            if (_syncWeek == 0) {
                              _syncWeek = _getWeekNumber(DateTime(_syncYear, _syncMonth, 1));
                            }
                          } else if (v == "月単位") {
                            _syncScope = "月単位";
                          } else if (v == "年単位") {
                            _syncScope = "年単位";
                          } else if (v == "全期間") {
                            _syncScope = "全期間"; 
                          }
                          // ------------------------------------
                        }); 
                      }
                    },
                  ),
                  Text(pScope, style: const TextStyle(fontSize: 12)),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 15),
          // --- ここから：選択期間に応じたデータの再抽出と集計ロジックを挿入 ---
          Builder(
            builder: (context) {
              List<dynamic> targetExpensesForPie = [];

              if (_pieScopeSelection == "週単位") {
                targetExpensesForPie = widget.allExpenses.where((e) {
                  if (e.date.length < 10) return false;
                  final date = DateTime.tryParse(e.date);
                  if (date == null) return false;
                  return date.year == _syncYear && date.month == _syncMonth && _getWeekNumber(date) == _syncWeek;
                }).toList();
              } else if (_pieScopeSelection == "月単位") {
                targetExpensesForPie = widget.allExpenses.where((e) {
                  return e.date.startsWith("$_syncYear-${_syncMonth.toString().padLeft(2, '0')}");
                }).toList();
              } else if (_pieScopeSelection == "年単位") {
                targetExpensesForPie = widget.allExpenses.where((e) {
                  return e.date.startsWith("$_syncYear-");
                }).toList();
              } else if (_pieScopeSelection == "全期間") {
                targetExpensesForPie = widget.allExpenses;
              }

              Map<String, int> activeCategorySums = {};
              int pieTotalAmount = 0;

              for (var e in targetExpensesForPie) {
                final amountInt = (e.amount as num).toInt(); 
                activeCategorySums[e.category] = (activeCategorySums[e.category] ?? 0) + amountInt;
                pieTotalAmount += amountInt;
              }

              final double denominator = pieTotalAmount == 0 ? 1.0 : pieTotalAmount.toDouble();

              // 抽出したデータが空ならメッセージを表示
              if (activeCategorySums.isEmpty) {
                return const Center(child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.0),
                  child: Text("指定期間のグラフデータがありません。"),
                ));
              }

              // データがある場合は円グラフと凡例を描画
              return Column(
                children: [
                  SizedBox(
                    height: 220,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: activeCategorySums.entries.map((entry) {
                          return PieChartSectionData(
                            color: widget.categoryColorMap[entry.key] ?? Colors.grey,
                            value: entry.value.toDouble(),
                            title: '${(entry.value / denominator * 100).toStringAsFixed(1)}%',
                            radius: 50,
                            titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Wrap(
                    spacing: 8, runSpacing: 4,
                    children: activeCategorySums.entries.map((entry) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 12, height: 12, color: widget.categoryColorMap[entry.key]),
                          const SizedBox(width: 4),
                          Text("${entry.key}: ${NumberFormat('#,###').format(entry.value)}円", style: const TextStyle(fontSize: 11)),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal)),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth = _getDaysInMonth(_syncYear, _syncMonth);
    
    // 1日の曜日を取得 (1: 月曜日, ..., 6: 土曜日, 7: 日曜日)
    final firstDayWeekday = DateTime(_syncYear, _syncMonth, 1).weekday;
    
    // 日曜日始まりのグリッドにするためのオフセット計算
    final firstDayOffset = firstDayWeekday == 7 ? 0 : firstDayWeekday;
    
    List<Widget> dayCells = [];
    final weekDays = ["日", "月", "火", "水", "木", "金", "土"];
    
    for (var w in weekDays) {
      dayCells.add(Container(
        alignment: Alignment.center,
        color: Colors.grey.shade300,
        padding: const EdgeInsets.all(4),
        child: Text(w, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: w == "日" ? Colors.red : (w == "土" ? Colors.blue : Colors.black))),
      ));
    }

    // 1日の曜日より前の空白マスを生成
    for (int i = 0; i < firstDayOffset; i++) {
      dayCells.add(Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
        ),
      ));
    }

    // 各日付マスの生成
    for (int day = 1; day <= daysInMonth; day++) {
      String dateStr = "$_syncYear-${_syncMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}";
      
      var dayExpenses = widget.allExpenses.where((e) => e.date == dateStr).toList();
      Map<String, int> catSum = {};
      int totalAmount = 0;
      for (var e in dayExpenses) { 
        catSum[e.category] = (catSum[e.category] ?? 0) + e.amount; 
        totalAmount += e.amount;
      }
      
      DateTime currentCellDate = DateTime(_syncYear, _syncMonth, day);
      bool isHighlighted = (_syncScope == "週単位" && _getWeekNumber(currentCellDate) == _syncWeek);
      
      // カテゴリの種類が3つ以上あるか判定
      bool isOverflow = catSum.keys.length >= 3;

      dayCells.add(
        GestureDetector(
          onTap: () {
            // 3つ以上の場合は、まず内訳ダイアログを表示
            if (isOverflow) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text("📅 $dateStr の支出内訳"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...catSum.entries.map((entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: widget.categoryColorMap[entry.key] ?? Colors.teal,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Text("${entry.value} 円", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )).toList(),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("合計", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                          Text("$totalAmount 円", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("閉じる"),
                    ),
                  ],
                ),
              );
            }

            // 週単位の集計への切り替え連動
            setState(() {
              _syncScope = "週単位";
              _syncWeek = _getWeekNumber(currentCellDate);
              _pieScopeSelection = "週単位";
            });
          },
          child: Container(
            decoration: BoxDecoration(
              // 3つ以上の場合は薄紫 (0xFFE8E5F5) を優先、それ以外は浅緑ハイライト
              color: isOverflow 
                  ? const Color(0xFFE8E5F5) 
                  : (isHighlighted ? const Color(0xFFE2F0D9) : Colors.white),
              border: Border.all(color: Colors.grey.shade200, width: 0.5),
            ),
            padding: const EdgeInsets.all(2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$day", 
                  style: TextStyle(
                    fontSize: 10, 
                    fontWeight: FontWeight.bold,
                    color: (day + firstDayOffset) % 7 == 1 ? Colors.red : ((day + firstDayOffset) % 7 == 0 ? Colors.blue : Colors.black87)
                  )
                ),
                Expanded(
                  child: isOverflow
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              "合計:$totalAmount円",
                              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.purple),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: catSum.entries.map((entry) {
                            return Container(
                              margin: const EdgeInsets.only(top: 1),
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(color: (widget.categoryColorMap[entry.key] ?? Colors.teal).withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                              child: Text("${entry.value}円", style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ); 
    }

    // グリッドを綺麗な長方形（7の倍数のマス数）にするための末尾の空白マス埋め
    final totalCells = dayCells.length - 7;
    final remainingCells = (7 - (totalCells % 7)) % 7;
    for (int i = 0; i < remainingCells; i++) {
      dayCells.add(Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
        ),
      ));
    }

    return Card(
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: dayCells,
      ),
    );
  } 
}