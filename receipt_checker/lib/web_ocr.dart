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
          
          // レシートの行を塊で飛ばさず、上から順に一行ずつスキャンさせる設定 (4: Assume a single column of text of variable sizes)
          await worker.setParameters({
            tessedit_pageseg_mode: '4',
            preserve_interword_spaces: '1'
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