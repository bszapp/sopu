/// 曲谱渲染页(flutter_inappwebview):
/// - cc ccmz: Detail 页已把 ccmz → data.ccxml|score.json 解出, 传入 scoreJson,
///   WebView 内 Vue2 + SvgScore 渲染(属性与 ccmz-tool ScorePdf.ts 一字对应)。
/// - tan8: 内联渲染 zix zip 解出的 .svg 序列。
/// 本地资产全部一次性内嵌(vue.min.js / xmlscore.p.js / music.woff data URI),
/// 数据经 `window._receiveChunk(i,n,b64)` 分块注入, 到齐后 `window._trigger()`
/// 解码 utf-8 → JSON → 渲染。Windows 走临时文件 file:// 加载, 移动端走 initialData。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

import '../utils/platform_utils.dart';
import '../utils/tan8_svg.dart';
import '../widgets/common.dart' show pageBottomScrollSpace;

WebViewEnvironment? _webEnv; // 由 main.dart 在 Windows 下注入

void initWebViewEnv(WebViewEnvironment? env) => _webEnv = env;

class SheetWebPage extends StatefulWidget {
  final String mode; // 'ccmz' | 'svg'
  final String title;
  final String scoreJson; // ccmz: data.ccxml|score.json 原文
  final String infoJson; // ccmz: info.json 原文(预留 meta)
  final List<String> svgs; // tan8: svg 序列

  const SheetWebPage.ccmz({
    super.key,
    required this.title,
    required this.scoreJson,
    this.infoJson = '',
  }) : mode = 'ccmz',
       svgs = const [];

  const SheetWebPage.svg({super.key, required this.title, required this.svgs})
    : mode = 'svg',
      scoreJson = '',
      infoJson = '';

  @override
  State<SheetWebPage> createState() => _SheetWebPageState();
}

class _SheetWebPageState extends State<SheetWebPage> {
  InAppWebViewController? _ctl;
  bool _start = false; // 已发出分块
  int? _renderedPages;
  InAppWebViewController? get webViewController => _ctl;
  String? _error;
  String? _htmlPath; // windows 用临时文件
  String? _htmlData; // 其余平台用 initialData

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final html = await _buildHtml();
      if (PlatformUtils.isDesktop) {
        final p =
            '${Directory.systemTemp.path}/sheet_${DateTime.now().millisecondsSinceEpoch}.html';
        await File(p).writeAsString(html, encoding: utf8);
        if (!mounted) return;
        setState(() => _htmlPath = p);
      } else {
        if (!mounted) return;
        setState(() => _htmlData = html);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '模板构建失败: $e');
    }
  }

  /// vue + xmlscore.p.js + woff 振型字型融合到静态模板。
  static Future<String> _buildHtml() async {
    final vue = (await rootBundle.loadString('assets/ccmz/vue.min.js'))
        .replaceAll('</script', '<\\/script');
    final core = (await rootBundle.loadString('assets/ccmz/xmlscore.p.js'))
        .replaceAll('</script', '<\\/script');
    final woffB64 = base64.encode(
      (await rootBundle.load('assets/ccmz/music.woff')).buffer.asUint8List(),
    );
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; font-src data:; img-src data: blob:; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<meta name="viewport" content="width=device-width,initial-scale=1">
<script>$vue</script>
<style>
@font-face{font-family:'Aloisen New';src:url(data:font/woff;base64,$woffB64) format('woff');font-display:block;}
html,body{margin:0;padding:0;background:#3a3a3a;}
body{padding-bottom:${pageBottomScrollSpace.toInt()}px;}
svg{display:block;width:100% !important;height:auto !important;page-break-after:always;break-after:page;background:#fff;}
.scorefont[data-v-1d111dd8]{font-family:'Aloisen New',Arial,serif;}
</style>
<script>$core</script>
<script>
window._parts = [];
window._total = 0;
window.__done = false;
window.__err = '';
window.__pages = 0;
window.addEventListener('error', function(e) { window.__err = String(e.message || e.error); });
window.addEventListener('unhandledrejection', function(e) { window.__err = String(e.reason); });
if (window.Vue) window.Vue.config.errorHandler = function(e) { window.__err = String(e); };
window._receiveChunk = function(i, n, b64) {
  window._total = n;
  window._parts[i] = b64;
  var loaded = 0;
  for (var k = 0; k < n; k++) if (window._parts[k] != null) loaded++;
  if (loaded === n) window.__ready = true;
};
window._assemble = function() {
  var s = window._parts.filter(function(x){return x != null;}).join('');
  var bin = atob(s);
  var bytes = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder('utf-8').decode(bytes);
};
window._status = function() {
  if (window.__done) return 'done:' + window.__pages;
  if (window.__err) return 'err:' + window.__err;
  var loaded = 0;
  for (var k = 0; k < window._total; k++) if (window._parts[k] != null) loaded++;
  return 'load:' + loaded + '/' + window._total;
};
function renderCcmz(jsonText) {
  try {
    var score = JSON.parse(jsonText);
    var Vue2 = window.Vue;
    if (!Vue2 || !window.SvgScore) throw new Error('谱面组件未初始化');
    var vm = new Vue2({
      render: function(h) {
        return h(window.SvgScore, {
          props: {
            score: score,
            lineh: 10,
            config: { display: 'onepage', showall: true, displayParam: { paged: true } }
          }
        });
      }
    }).\$mount('#app');
    Vue2.nextTick(function() {
      Promise.all([document.fonts.load('1em "Aloisen New"'), document.fonts.ready]).then(function() {
        requestAnimationFrame(function() {
          if (window.__err) return;
          var svg = vm.\$el;
          if (!svg || !svg.querySelectorAll) { window.__err = '谱面组件未生成 SVG'; return; }
          var pages = svg.querySelectorAll('g[id^="page_"]').length;
          var shapeCount = svg.querySelectorAll('path,line,rect,text,use').length;
          if (!pages || !shapeCount || svg.getBoundingClientRect().height <= 0) {
            window.__err = '谱面未生成有效图形'; return;
          }
          window.__pages = pages;
          window.__done = true;
        });
      });
    });
  } catch (e) {
    console.error(e);
    window.__err = '渲染失败: ' + e;
    document.title = 'ERR';
  }
}
function renderSvgPages(svgList) {
  try {
    var app = document.getElementById('app');
    svgList.forEach(function(s) {
      var d = document.createElement('div');
      d.innerHTML = s;
      app.appendChild(d);
    });
    window.__pages = app.querySelectorAll('svg').length;
    if (!window.__pages || !app.querySelector('path,line,rect,text,use')) throw new Error('未生成 SVG 图形');
    window.__done = true;
  } catch (e) {
    console.error(e);
    window.__err = '渲染失败: ' + e;
  }
}
window._trigger = function() {
  try {
    var text = window._assemble();
    if (window.__mode === 'ccmz') { renderCcmz(text); }
    else { renderSvgPages(JSON.parse(text)); }
  } catch (e) {
    console.error(e);
    window.__err = '数据解析失败: ' + e;
  }
};
</script>
</head>
<body>
<div id="app"></div>
</body>
</html>
''';
  }

  /// 对自渲染内容统一 utf8 → b64 → 分块注入。
  /// ccmz: scoreJson 原文; svg: JSON.stringify(svg 序列)。
  List<String> _payloadB64() {
    final text = widget.mode == 'ccmz'
        ? widget.scoreJson
        : json.encode([for (final s in widget.svgs) removeTan8Watermarks(s)]);
    final b64 = base64.encode(utf8.encode(text));
    const chunk = 380000; // 原始 380KB → b64 ~507KB/块
    final out = <String>[];
    for (var i = 0; i < b64.length; i += chunk) {
      out.add(
        b64.substring(i, (i + chunk) < b64.length ? i + chunk : b64.length),
      );
    }
    if (out.isEmpty) out.add('');
    return out;
  }

  Future<void> _pumpChunks(InAppWebViewController ctl) async {
    if (_start) return;
    _start = true;
    final parts = _payloadB64();
    await ctl.evaluateJavascript(
      source:
          "window.__mode='${widget.mode}';window._parts=[];window._total=0;",
    );
    for (var i = 0; i < parts.length; i++) {
      await ctl.evaluateJavascript(
        source: "window._receiveChunk($i,${parts.length},'${parts[i]}');",
      );
    }
    await ctl.evaluateJavascript(source: 'window._trigger();');
    _pollDone();
  }

  Future<void> _pollDone() async {
    for (var i = 0; i < 480; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      String? st;
      try {
        st = await _ctl?.evaluateJavascript(source: 'window._status()');
      } catch (_) {}
      final s = '$st';
      if (s.contains('done:')) {
        SmartDialog.showToast('谱面加载完成(${s.split(':').last}页)');
        if (mounted) {
          setState(() => _renderedPages = int.tryParse(s.split(':').last));
        }
        return;
      }
      if (s.startsWith('err:')) {
        if (mounted) setState(() => _error = s.replaceFirst('err:', ''));
        SmartDialog.showToast(_error!);
        return;
      }
    }
    if (mounted) setState(() => _error = '渲染超时');
  }

  @override
  void dispose() {
    if (_htmlPath != null) {
      final f = File(_htmlPath!);
      if (f.existsSync()) f.deleteSync();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _renderedPages == null
              ? widget.title
              : '${widget.title} · $_renderedPages 页',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _error != null
          ? Center(
              child: Text(_error!, style: TextStyle(color: c.error)),
            )
          : (_htmlData == null && _htmlPath == null)
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
              webViewEnvironment: _webEnv,
              initialData: _htmlData != null
                  ? InAppWebViewInitialData(
                      data: _htmlData!,
                      mimeType: 'text/html',
                      encoding: 'utf-8',
                    )
                  : null,
              initialUrlRequest: _htmlPath == null
                  ? null
                  : URLRequest(url: WebUri(Uri.file(_htmlPath!).toString())),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: false,
                useWideViewPort: true,
                supportZoom: true,
                blockNetworkImage: true,
                blockNetworkLoads: true,
              ),
              onWebViewCreated: (ctl) => _ctl = ctl,
              onLoadStop: (ctl, _) => _pumpChunks(ctl),
            ),
    );
  }
}
