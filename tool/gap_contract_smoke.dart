import 'dart:convert';
import 'dart:io';

import 'package:sopu/http/http.dart';
import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/utils/data_fields.dart';

// 仅工作台进程读取系统代理；应用运行时不包含代理配置。
class ProbeProxy extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    final proxy = Platform.environment['SOPU_TOOL_PROXY'];
    if (proxy != null && proxy.isNotEmpty) {
      client.findProxy = (_) => 'PROXY $proxy';
    }
    return client;
  }
}

Future<void> main(List<String> args) async {
  HttpOverrides.global = ProbeProxy();
  Http.init();
  final report = <Map<String, dynamic>>[];
  Future<bool> check(String api, Future<Object> Function() run) async {
    try {
      final evidence = await run();
      report.add({'api': api, 'status': 'PASS', 'evidence': evidence});
      stdout.writeln('PASS $api ${jsonEncode(evidence)}');
      return true;
    } catch (e) {
      report.add({'api': api, 'status': 'FAIL', 'error': '$e'});
      stdout.writeln('FAIL $api $e');
      return false;
    }
  }

  var publicOk = true;
  publicOk &= await check('cc.userProfile', () async {
    final d = await CcApi.userProfile('956300');
    if (!['${d['uid']}', '${d['cg_uid']}'].contains('956300')) {
      throw StateError('目标用户身份不匹配');
    }
    return {
      'name': userNameOf(d).isNotEmpty,
      'photo': userPhotoOf(d, 'cc').isNotEmpty,
      'phoneExcluded': !d.containsKey('phone'),
    };
  });
  publicOk &= await check('tan8.userProfile', () async {
    final d = await Tan8Api.userProfile('9823272');
    if ('${d['uid']}' != '9823272' || d.containsKey('phone')) {
      throw StateError('身份或隐私字段不匹配');
    }
    return {
      'name': userNameOf(d).isNotEmpty,
      'photo': userPhotoOf(d, 'tan8').isNotEmpty,
      'phoneExcluded': true,
    };
  });
  publicOk &= await check('cc.commentReplies.pages', () async {
    final a =
        (await CcApi.commentReplies('5686738', page: 1, size: 3))['list_reply']
            as List;
    final b =
        (await CcApi.commentReplies('5686738', page: 2, size: 3))['list_reply']
            as List;
    final first = a.whereType<Map>().map(commentIdOf).toSet(),
        second = b.whereType<Map>().map(commentIdOf).toSet();
    if (a.isEmpty || b.isEmpty || first.intersection(second).isNotEmpty) {
      throw StateError('分页为空或存在重叠');
    }
    return {'page1': a.length, 'page2': b.length, 'overlap': 0};
  });
  publicOk &= await check('cc.detail.newLearningId', () async {
    final d = await CcApi.opernDetail('36583');
    final id = textOf(d, ['id', 'learning_id']);
    if (id.isEmpty) throw StateError('详情缺少新体系 ID');
    return {'old_id': '36583', 'learning_id': id, 'distinct': id != '36583'};
  });
  final session = Platform.environment['SOPU_TEST_CC_SESSION'] ?? '';
  if (publicOk && session.isNotEmpty) {
    CcApi.phpSessionId = session;
    final identityFile = Platform.environment['SOPU_TEST_CC_IDENTITY_FILE'];
    if (identityFile != null && identityFile.isNotEmpty) {
      final identity =
          jsonDecode(await File(identityFile).readAsString()) as Map;
      CcApi.uid = '${identity['uid'] ?? ''}';
      CcApi.serviceUid = '${identity['service_uid'] ?? ''}';
      CcApi.serviceKey = '${identity['service_key'] ?? ''}';
      CcApi.userToken = '${identity['user_id'] ?? ''}';
      CcApi.cgUid = '${identity['cg_uid'] ?? identity['service_uid'] ?? ''}';
      await check('cc.collectCheck.positiveAndNegative', () async {
        final positive = await CcApi.collectCheck('1072807');
        final negative = await CcApi.collectCheck('979814');
        if ('${positive['has_collect']}' != '1' ||
            '${negative['has_collect']}' != '0') {
          throw StateError('收藏正反样本与已验记录不符，需核对当前收藏');
        }
        return {'positive': true, 'negative': true};
      });
    }
    await check('cc.history.tables', () async {
      final combined = await CcApi.combinedBrowseHistory();
      final rows = combined['list'] as List;
      return {
        'merged': rows.length,
        'warnings': (combined['warnings'] as List).length,
      };
    });
    if (args.contains('--write')) {
      await check('cc.reportBrowse.existingRecord', () async {
        final before = itemsOf(await CcApi.myLearningHistory());
        final usedExisting = before.isNotEmpty && before.first is Map;
        final detail = usedExisting
            ? before.first as Map
            : await CcApi.opernDetail('1144422');
        final id = textOf(
          detail,
          usedExisting ? ['learning_id', 'id'] : ['id', 'learning_id'],
        );
        if (id.isEmpty) throw StateError('缺少新体系 ID');
        await CcApi.reportBrowse(id);
        final after = itemsOf(await CcApi.myLearningHistory());
        if (!after.whereType<Map>().any(
          (row) => textOf(row, ['learning_id', 'id']) == id,
        )) {
          throw StateError('上报后学习表无该谱');
        }
        return {
          'postAccepted': true,
          'readback': true,
          'usedExistingRecord': usedExisting,
        };
      });
    }
  }
  if (args.isNotEmpty && args.first != '--write') {
    await File(args.first)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  }
  Http.tan8.close(force: true);
  Http.cc.close(force: true);
  if (report.any((r) => r['status'] == 'FAIL')) exitCode = 1;
}
