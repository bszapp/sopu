import 'dart:convert';
import 'dart:io';

import 'package:sopu/http/cc_api.dart';
import 'package:sopu/http/http.dart';
import 'package:sopu/http/tan8_api.dart';
import 'package:sopu/utils/data_fields.dart';

Future<void> main(List<String> args) async {
  final dir = Directory(args[0]);
  final samples = jsonDecode(
    await File(args[1]).readAsString(),
  )['publicSamples'];
  Http.init(cookieDir: '${dir.path}/cookies');
  final report = <Map<String, dynamic>>[];
  Future<void> check(String name, Future<Object?> Function() run) async {
    try {
      final result = await run();
      report.add({'api': name, 'status': 'PASS', 'evidence': result});
      stdout.writeln('PASS $name $result');
    } catch (e) {
      report.add({'api': name, 'status': 'FAIL', 'error': '$e'});
      stdout.writeln('FAIL $name $e');
    }
  }

  try {
    final session = jsonDecode(
      await File('${dir.path}/cc_session.json').readAsString(),
    );
    CcApi.uid = session['uid'];
    CcApi.cgUid = session['cg_uid'];
    CcApi.userToken = session['id'];
    CcApi.serviceUid = session['service_uid'];
    CcApi.serviceKey = session['service_key'];
    CcApi.eqid = session['eqid'];
    await check('cc.me.displayFields', () async {
      final me = await CcApi.me();
      await File('${dir.path}/cc_session.json').writeAsString(
        jsonEncode({
          'uid': CcApi.uid,
          'cg_uid': CcApi.cgUid,
          'id': CcApi.userToken,
          'service_uid': CcApi.serviceUid,
          'service_key': CcApi.serviceKey,
          'eqid': CcApi.eqid,
        }),
      );
      return {
        'nameAvailable': userNameOf(me).isNotEmpty,
        'avatarAvailable': userPhotoOf(me, 'cc').isNotEmpty,
      };
    });
    await check('tan8.getUserInfo.displayFields', () async {
      final profile = await Tan8Api.getUserInfo();
      if (profile['user'] is! Map) throw StateError('测试会话已失效');
      return {
        'nameAvailable': userNameOf(profile['user']).isNotEmpty,
        'avatarAvailable': userPhotoOf(profile['user'], 'tan8').isNotEmpty,
      };
    });
    await check(
      'tan8.comments.hot.empty',
      () async => {
        'count': (await Tan8Api.comments(
          '125516',
          sort: 'hot',
          limit: 5,
        )).length,
      },
    );
    await check(
      'tan8.isCollected',
      () async => {'state': await Tan8Api.isCollected('125516')},
    );
    final publicComment = samples['tan8.comments.time'][0];
    final author = '${publicComment['uid']}';
    await check('tan8.isFollowing', () async {
      final me = await Tan8Api.getUserInfo();
      return {
        'state': await Tan8Api.isFollowing('${me['user']['uid']}', author),
      };
    });
    await check('tan8.authorWorks.pagination', () async {
      final seen = <String>{};
      final counts = <int>[];
      for (final start in [0, 5, 10]) {
        final modules = await Tan8Api.authorWorks(
          author,
          scope: 'collect',
          start: start,
          limit: 5,
        );
        final rows = modules
            .whereType<Map>()
            .expand((m) => itemsOf(m['result']['result']))
            .whereType<Map>();
        final ids = rows
            .map((e) => textOf(e, ['id']))
            .where((id) => id.isNotEmpty)
            .toList();
        if (ids.any(seen.contains)) throw StateError('不同页返回重复曲谱');
        seen.addAll(ids);
        counts.add(ids.length);
      }
      if (seen.length < 6) throw StateError('样例不足以确认翻页');
      return {'pageCounts': counts, 'uniqueCount': seen.length};
    });
    for (final platform in ['cc', 'tan8']) {
      await check('$platform.history.afterOpen', () async {
        Future<List<dynamic>> history() async => platform == 'cc'
            ? itemsOf(await CcApi.myBrowseHistory(size: 100))
            : await Tan8Api.myBrowseHistory(limit: 100);
        String scoreId(dynamic row) => row is Map<String, dynamic>
            ? textOf(scoreData(row), ['old_id', 'yuepuid', 'id'])
            : '';
        final before = await history();
        final candidates = platform == 'cc'
            ? ['36583', '971970', '1072807']
            : ['116415', '125516'];
        final target = candidates.firstWhere(
          (id) => !before.any((row) => scoreId(row) == id),
          orElse: () => candidates.first,
        );
        if (platform == 'cc') {
          await CcApi.opernDetail(target);
        } else {
          await Tan8Api.scoreInfo(target);
        }
        final after = await history();
        if (after.isNotEmpty && after.first is Map) {
          final row = after.first as Map;
          stdout.writeln('$platform.history.fields ${row.keys.join(',')}');
          for (final entry in row.entries.where((e) => e.value is Map)) {
            stdout.writeln(
              '$platform.history.${entry.key}.fields ${(entry.value as Map).keys.join(',')}',
            );
          }
        }
        final recorded = after.any((row) => scoreId(row) == target);
        if (!recorded) {
          throw StateError('详情请求完成后，历史列表未出现测试曲谱 $target（返回 ${after.length} 条）');
        }
        return {'recorded': true, 'count': after.length};
      });
    }
    await check('tan8.myPlaylists.contract', () async {
      final value = await Tan8Api.myPlaylists();
      return {'type': 'List', 'count': value.length, 'empty': value.isEmpty};
    });
    await File('${dir.path}/repair_reads.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    if (report.any((r) => r['status'] == 'FAIL')) exitCode = 1;
  } finally {
    Http.tan8.close(force: true);
    Http.cc.close(force: true);
  }
}
