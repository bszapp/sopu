import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sopu/widgets/piliplus/score_card_h.dart';

void main() {
  testWidgets('曲谱列表展示曲名、上传者、VIP 与 AI 标记', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScoreCardH({
            '__platform': 'tan8',
            'id': '125516',
            'name': '曲谱名称',
            'maskName': '上传者名称',
            'isvip': '1',
            'showAIScrollScoreIcon': '1',
          }),
        ),
      ),
    );
    expect(find.text('曲谱名称'), findsOneWidget);
    expect(find.text('上传者名称'), findsOneWidget);
    expect(find.text('VIP'), findsOneWidget);
    expect(find.text('AI 谱'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('虫虫单谱价格与作者会员字段分开展示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScoreCardH({
            '__platform': 'cc',
            'old_id': '1072807',
            'name': '付费谱',
            'upload_user_name': '作者',
            'is_vip': '1',
            'paytype': '3',
            'is_pay': '1',
            'sale_price': '6.00',
            'play_json': '/score.ccmz',
          }),
        ),
      ),
    );
    expect(find.text('¥6.00'), findsOneWidget);
    expect(find.text('VIP'), findsNothing);
    expect(find.text('AI 谱'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
