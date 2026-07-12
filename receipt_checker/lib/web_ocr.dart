import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

class ReceiptOcrService {
  final String _apiKey;

  ReceiptOcrService(this._apiKey);

  /// レシートの画像バイトデータを基に、Geminiを用いて構造化データを抽出します
  Future<Map<String, dynamic>> analyzeReceipt(Uint8List imageBytes) async {
    // 2026年現在の最新の高速・高精度マルチモーダルモデルを使用
    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: Schema.object(
          properties: {
            'date': Schema.string(
                description: 'レシートの取引日付。YYYY-MM-DD形式。不明な場合は本日の日付。'),
            'storeName': Schema.string(
                description: 'レシートを発行した店舗名（例: セブン-イレブン、BOOKOFFなど）。無駄な住所や電話番号は含めない。'),
            'items': Schema.array(
              items: Schema.string(description: '購入された個々の商品名やサービス名。'),
            ),
            'amount': Schema.integer(
                description: '支払い合計金額（税込）。割引やポイント利用後の最終支払額、または「合計」「合計金額」と書かれた金額。数値のみ。'),
            'category': Schema.string(
                description: '購入内容から推測される適切な家計簿カテゴリ（例: 食費、日用品、娯楽費、通信費など）。'),
          },
        ),
      ),
    );

    final prompt = TextPart(
      'このレシート画像から、「取引日付」「店名」「購入した商品名のリスト」「合計金額（税込）」「適切な家計簿カテゴリ」を抽出してください。\n'
      '・店名はロゴやテキストから総合的に判断し、最も適切な名称を抽出してください。\n'
      '・金額はお釣りや小計ではなく、最終的な「合計（TAX incl.）」の数字のみを抽出してください。\n'
      '・商品名は改行区切りのテキストとして後で扱いやすいため、リスト形式で漏れなく抽出してください。'
    );

    final imagePart = DataPart('image/png', imageBytes);

    try {
      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      final jsonText = response.text;
      if (jsonText == null || jsonText.isEmpty) {
        throw Exception('Geminiからの応答が空でした。');
      }

      // JSON文字列をパースしてMapとして返却
      return jsonDecode(jsonText) as Map<String, dynamic>;
    } catch (e) {
      print('OCR解析エラー: $e');
      rethrow;
    }
  }
}