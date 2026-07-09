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
          
          await worker.setParameters({
            tessedit_pageseg_mode: '3', // 自動配置判定
            preserve_interword_spaces: '1'
          });
          
          const { data } = await worker.recognize('$base64Image');
          await worker.terminate();

          // スマホ特有の「改行の崩れ」対策として、1行ずつきれいに成形して結合
          const lines = data.lines.map(l => {
            let t = l.text.trim();
            // 認識精度を下げる細かいゴミ記号（. , _ ~ など）を最低限ブラウザ側で掃除
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