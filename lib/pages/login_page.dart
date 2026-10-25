/// 登录页: 双平台短信登录 (弹琴吧 sendMessage/messageLogin / 虫虫 SendSmsNew/LoginByCode)。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import '../http/cc_api.dart';
import '../http/http.dart';
import '../http/tan8_api.dart';
import '../services/sessions.dart';
import '../widgets/common.dart';

class LoginPage extends StatefulWidget {
  final String platform; // 'cc' | 'tan8'
  const LoginPage({super.key, required this.platform});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  int _countdown = 0;
  Timer? _timer;
  String _info = '';
  bool _sending = false;
  bool _loggingIn = false;
  bool get isCc => widget.platform == 'cc';

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_sending || _countdown > 0 || _loggingIn) return;
    final phone = _phone.text.replaceAll(RegExp(r'\s+'), '');
    if (phone.isEmpty || phone.length < 5) {
      SmartDialog.showToast('请输入手机号');
      return;
    }
    setState(() => _sending = true);
    try {
      String message;
      if (isCc) {
        final d = await CcApi.sendCode(phone);
        message = '${d['returnMsg'] ?? '服务器已受理，请等待短信'}';
      } else {
        final d = await Tan8Api.sendCode(phone);
        if (!['1000', '1'].contains('${d['code']}')) {
          throw Tan8ApiError(
            '${d['code']}',
            '${d['message'] ?? d['msg'] ?? ''}',
          );
        }
        message = '${d['message'] ?? d['msg'] ?? '服务器已受理，请等待短信'}';
      }
      if (!mounted) return;
      SmartDialog.showToast(message);
      setState(() {
        _info = message;
        _countdown = isCc ? CcApi.smsCooldownRemaining(phone) : 60;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(
          () => _countdown = isCc
              ? CcApi.smsCooldownRemaining(phone)
              : _countdown - 1,
        );
        if (_countdown <= 0) t.cancel();
      });
    } catch (e) {
      SmartDialog.showToast('发送失败: $e');
      if (mounted) setState(() => _info = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _login() async {
    if (_loggingIn || _sending) return;
    final phone = _phone.text.replaceAll(RegExp(r'\s+'), '');
    final code = _code.text.trim();
    if (phone.isEmpty || code.isEmpty) {
      SmartDialog.showToast('请输入手机号与验证码');
      return;
    }
    setState(() => _loggingIn = true);
    SmartDialog.showLoading(msg: '登录中');
    try {
      String name = '';
      if (isCc) {
        final info = await CcApi.loginByCode(phone, code);
        final profile = await CcApi.me().catchError((_) => <String, dynamic>{});
        Sessions.ccUser = {
          ...info,
          ...profile,
          'uid': CcApi.uid,
          'service_uid': CcApi.serviceUid,
          'service_key': CcApi.serviceKey,
          'id': CcApi.userToken,
          'cg_uid': CcApi.cgUid,
          'PHPSESSID': CcApi.phpSessionId,
        };
        await Sessions.saveCc();
        name = '${Sessions.ccUser['nickname'] ?? ''}';
      } else {
        final d = await Tan8Api.messageLogin(phone, code);
        if ('${d['code']}' != '1000') {
          throw Tan8ApiError('${d['code']}', '${d['message']}');
        }
        final u = await Tan8Api.getUserInfo();
        if ('${u['code']}' == '1000' && u['user'] is Map<String, dynamic>) {
          Sessions.tan8User = Map<String, dynamic>.from(u['user']);
        } else {
          throw const Tan8ApiError('NO_USERINFO', '登录后未取得用户资料');
        }
        await Sessions.saveTan8();
        name = '${Sessions.tan8User['webname'] ?? ''}';
      }
      SmartDialog.dismiss(status: SmartStatus.loading);
      if (!mounted) return;
      SmartDialog.showToast(
        isCc && CcApi.uid.isEmpty
            ? '登录会话已保存，账号资料尚未获取'
            : '登录成功${name.isEmpty ? '' : ': $name'}',
      );
      Get.back(result: true);
    } catch (e) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      SmartDialog.showToast('登录失败: $e');
      if (mounted) setState(() => _info = '$e');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            PlatformBadge(widget.platform, fontSize: 11),
            const SizedBox(width: 8),
            Text('登录${isCc ? '虫虫钢琴' : '弹琴吧'}'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: '手机号 (+86)',
              border: OutlineInputBorder(),
              prefixText: '+86 ',
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '短信验证码',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _countdown > 0 || _sending || _loggingIn
                    ? null
                    : _sendCode,
                child: Text(
                  _sending
                      ? '请求中…'
                      : _countdown > 0
                      ? '重发(${_countdown}s)'
                      : '发送验证码',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loggingIn || _sending ? null : _login,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            child: const Text('登录'),
          ),
          if (_info.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              _info,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            '说明: 短信登录由您在应用内主动发起;'
            ' 验证码仅用于登录, 成功后会话保存在本机',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
