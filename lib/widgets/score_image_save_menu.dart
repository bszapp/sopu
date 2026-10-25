import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/file_save_service.dart';
import 'piliplus/image_viewer/simple_dialog_option.dart';

Future<void> showScoreImageSaveMenu(
  BuildContext context, {
  required String title,
  required int index,
  required int count,
  required Future<Uint8List> Function(int index) imageAt,
}) async {
  if (count == 0) return;
  final all = await showDialog<bool>(
    context: context,
    builder: (context) => SimpleDialog(
      clipBehavior: Clip.hardEdge,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        DialogOption(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('保存图片', style: TextStyle(fontSize: 14)),
        ),
        if (count > 1)
          DialogOption(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存全部图片', style: TextStyle(fontSize: 14)),
          ),
      ],
    ),
  );
  if (all == null || !context.mounted) return;
  final pages = all ? List.generate(count, (i) => i) : [index];
  final progress = ValueNotifier(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('保存谱面'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (context, done, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: done / pages.length),
              const SizedBox(height: 16),
              Text('已处理 $done/${pages.length} 张'),
            ],
          ),
        ),
      ),
    ),
  );
  var saved = 0;
  String? error;
  final prefix =
      '${String.fromCharCodes(FileSaveService.safeName(title).runes.take(40))}_${DateTime.now().millisecondsSinceEpoch}';
  try {
    for (final page in pages) {
      try {
        await FileSaveService.saveImage(
          '${prefix}_${page + 1}',
          await imageAt(page),
        );
        saved++;
      } catch (e) {
        error ??= e is PlatformException ? e.message ?? e.code : '$e';
        // 授权拒绝后停止，避免保存全部时反复申请权限。
        if (e is PlatformException && e.code == 'PERMISSION_DENIED') break;
      }
      progress.value++;
    }
  } finally {
    if (navigator.mounted) navigator.pop();
    await dialog;
    progress.dispose();
  }
  if (!context.mounted) return;
  const target = '相册 · Pictures/搜谱';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error == null
            ? '已保存 $saved 张 → $target'
            : '已保存 $saved/${pages.length} 张${saved > 0 ? ' → $target' : ''}；$error',
      ),
    ),
  );
}
