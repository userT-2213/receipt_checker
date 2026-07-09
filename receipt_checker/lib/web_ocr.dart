import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:image_picker/image_picker.dart';

Future<String> runTesseractWeb(XFile pickedFile) async {
  try {
    final bytes = await pickedFile.readAsBytes();
    final base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
    final completer = Completer<String>();
    
    js.context['runTesseractCallback'] = js.allowInterop((String text) {
      completer.complete(text);
    });

    // eval内で非同期即時関数を実行し、確実に全行を個別に取得して結合する
    js.context.callMethod('eval', [
      """
      (async () => {
        try {
          const worker = await Tesseract.createWorker('jpn');
          
          // 日本語レシート用にパラメータを最適化
          await worker.setParameters({
            tessedit_pageseg_mode: '3', // 自動判定に戻し、横並びの文字崩れを防止
            preserve_interword_spaces: '1',
            // 認識対象をレシート頻出文字に絞り込み、謎の漢字への誤変換を防止
            tessedit_char_whitelist: '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ円点個、。×¥￥-+:/()「」' + 
                                     'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲンー' +
                                     'あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん' +
                                     '日月火水木金土時分秒年領収書小計合計合計金額お預りお釣御厳急店ナインイレブンフライドチキン冷やし中華'
          });
          
          const { data } = await worker.recognize('$base64Image');
          await worker.terminate();

          // 認識された各行のテキストを強制的に安全な特殊区切り文字[LINE]で結合する
          const lines = data.lines.map(l => l.text.trim()).filter(t => t.length > 0);
          runTesseractCallback(lines.join('[LINE]'));
        } catch (err) {
          runTesseractCallback('JS_ERROR: ' + err.toString());
        }
      })();
      """
    ]);

    return await completer.future;
  } catch (e) {
    return "DART_ERROR: \$e";
  }
}