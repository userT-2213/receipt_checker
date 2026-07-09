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

    js.context.callMethod('eval', [
      """
      (async () => {
        try {
          const worker = await Tesseract.createWorker('jpn');
          
          // 不具合の原因になりやすいホワイトリストは廃止し、自動判定モードに最適化
          await worker.setParameters({
            tessedit_pageseg_mode: '3', // 自動判定に戻して横並びの文字崩れを防止
            preserve_interword_spaces: '1'
          });
          
          const { data } = await worker.recognize('$base64Image');
          await worker.terminate();

          // 認識された各行のテキストを整形して結合
          const lines = data.lines.map(l => {
            let t = l.text.trim();
            // 精度を低下させる細かなゴミ記号（. , _ ~ など）を最低限ブラウザ側で掃除
            t = t.replace(/[.,_~^`']/g, '');
            return t;
          }).filter(t => t.length > 0);
          
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