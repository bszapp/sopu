/// 我的页面: 双平台账号卡 + 登录入口 + 我的收藏(按平台分区)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../services/sessions.dart';
import '../http/cc_api.dart';
import '../http/tan8_api.dart';
import 'login_page.dart';
import 'author_page.dart';
import '../widgets/common.dart';
import '../utils/data_fields.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的'), centerTitle: false),
      body: ValueListenableBuilder<int>(
        valueListenable: Sessions.changed,
        builder: (context, _, _) => ListView(
          padding: EdgeInsets.zero,
          children: [
            _AccountCard(platform: 'cc'),
            _AccountCard(platform: 'tan8'),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('浏览历史'),
              onTap: () => _openList('history'),
            ),
            if (Sessions.tan8LoggedIn) ..._tan8Lists(context),
            if (Sessions.ccLoggedIn) ..._ccLists(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _tan8Lists(BuildContext context) => [
    ListTile(
      leading: const Icon(Icons.collections_bookmark_outlined),
      title: const Text('我的收藏(弹琴吧)'),
      onTap: () => _openList('tan8_collect'),
    ),
    ListTile(
      leading: const Icon(Icons.group_outlined),
      title: const Text('关注列表(弹琴吧)'),
      onTap: () => _openList('tan8_follow'),
    ),
    ListTile(
      leading: const Icon(Icons.people_outline),
      title: const Text('粉丝列表(弹琴吧)'),
      onTap: () => _openList('tan8_fans'),
    ),
    ListTile(
      leading: const Icon(Icons.thumb_up_outlined),
      title: const Text('我的点赞(弹琴吧)'),
      onTap: () => _openList('tan8_likes'),
    ),
    ListTile(
      leading: const Icon(Icons.queue_music),
      title: const Text('我的歌单(弹琴吧)'),
      onTap: () => _openList('tan8_playlists'),
    ),
  ];

  List<Widget> _ccLists(BuildContext context) => [
    ListTile(
      leading: const Icon(Icons.collections_bookmark_outlined),
      title: const Text('我的收藏(虫虫)'),
      onTap: () => _openList('cc_collect'),
    ),
    ListTile(
      leading: const Icon(Icons.group_outlined),
      title: const Text('关注列表(虫虫)'),
      onTap: () => _openList('cc_follow'),
    ),
    ListTile(
      leading: const Icon(Icons.people_outline),
      title: const Text('粉丝列表(虫虫)'),
      onTap: () => _openList('cc_fans'),
    ),
  ];

  void _openList(String kind) {
    Get.toNamed('/mine_list', parameters: {'kind': kind});
  }
}

class _AccountCard extends StatelessWidget {
  final String platform;
  const _AccountCard({required this.platform});

  @override
  Widget build(BuildContext context) {
    final isCc = platform == 'cc';
    final user = isCc ? Sessions.ccUser : Sessions.tan8User;
    final loggedIn = user.isNotEmpty;
    final name = userNameOf(user);
    final photo = userPhotoOf(user, platform), member = membershipOf(user);
    final uid = userIdOf(user, platform);
    void openProfile() {
      final ownUid = isCc ? Sessions.ccNumericId : Sessions.tan8Uid;
      if (ownUid.isEmpty) {
        SmartDialog.showToast('登录资料缺少用户 ID，请刷新个人信息后重试');
        return;
      }
      Get.to(
        () => AuthorPage(
          platform: platform,
          uid: ownUid,
          name: name,
          photo: photo,
        ),
        routeName: '/author/$platform/$ownUid',
        preventDuplicates: false,
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(url: photo, name: name),
                const SizedBox(width: 10),
                PlatformBadge(platform, fontSize: 11),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: loggedIn ? openProfile : null,
                    child: Text(
                      loggedIn ? (name.isEmpty ? '已登录' : name) : '未登录',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (member != null) StatusBadge(member),
                if (loggedIn)
                  Text(
                    isCc
                        ? (Sessions.ccNumericId.isEmpty
                              ? uid
                              : Sessions.ccNumericId)
                        : uid,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (loggedIn)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: openProfile,
                  icon: const Icon(Icons.person_outline),
                  label: const Text('我的主页'),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () async {
                      if (loggedIn) {
                        try {
                          final profile = isCc
                              ? await CcApi.me()
                              : (await Tan8Api.getUserInfo())['user'];
                          if (profile is! Map<String, dynamic>) {
                            throw StateError('服务器未返回用户资料');
                          }
                          if (isCc) {
                            Sessions.ccUser = {...Sessions.ccUser, ...profile};
                            await Sessions.saveCc();
                          } else {
                            Sessions.tan8User = profile;
                            await Sessions.saveTan8();
                          }
                          Get.dialog(
                            AlertDialog(
                              title: const Text('个人信息'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    UserAvatar(
                                      url: userPhotoOf(profile, platform),
                                      name: userNameOf(profile),
                                      radius: 36,
                                    ),
                                    const SizedBox(height: 12),
                                    if (membershipOf(profile) != null)
                                      StatusBadge(membershipOf(profile)!),
                                    for (final entry in <String, String>{
                                      '昵称': userNameOf(profile),
                                      '用户 ID': userIdOf(profile, platform),
                                      '简介': textOf(profile, [
                                        'personal_profile',
                                        'self_introduction',
                                        'signature',
                                        'intro',
                                      ]),
                                      '地区': textOf(profile, [
                                        'address',
                                        'city',
                                        'province',
                                      ]),
                                      '生日': textOf(profile, ['birthday']),
                                      '关注': textOf(profile, [
                                        'total_follow_num',
                                        'followCount',
                                      ]),
                                      '粉丝': textOf(profile, [
                                        'total_fans_num',
                                        'fansCount',
                                      ]),
                                      '发布曲谱': textOf(profile, [
                                        'total_opern_num',
                                        'yuepuPublishCount',
                                      ]),
                                      '收藏曲谱': textOf(profile, [
                                        'yuepuCollectCount',
                                      ]),
                                    }.entries)
                                      if (entry.value.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            '${entry.key}：${entry.value}',
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Get.back(),
                                  child: const Text('关闭'),
                                ),
                              ],
                            ),
                          );
                        } catch (e) {
                          SmartDialog.showToast('读取失败: $e');
                        }
                      } else {
                        Get.to(() => LoginPage(platform: platform));
                      }
                    },
                    child: Text(loggedIn ? '个人信息' : '登录'),
                  ),
                ),
                if (loggedIn) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await Get.dialog<bool>(
                        AlertDialog(
                          title: Text('退出${isCc ? '虫虫' : '弹琴吧'}登录?'),
                          actions: [
                            TextButton(
                              onPressed: () => Get.back<bool>(result: false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Get.back<bool>(result: true),
                              child: const Text('确认'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        if (isCc) {
                          await Sessions.logoutCc();
                        } else {
                          await Sessions.logoutTan8();
                        }
                        SmartDialog.showToast('已退出');
                      }
                    },
                    child: const Text('退出'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
