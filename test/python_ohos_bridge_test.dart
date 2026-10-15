import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 两份 `QfliPyNative.ets` 副本必须逐字节相同。
///
/// 这是 Dart 侧唯一保留的 OHOS 断言，存在的理由很窄：只有进构建路径的那份
/// 会被编译，另一份（`native/ohos/`）漂了不会有任何编译错误、Dart 测试或
/// 真机自检能发现。它是一个纯文件系统事实，不是对实现的镜像断言。
///
/// 通道行为（取消/字节码/参数校验/token 生命周期）由真实 handler 行为测试
/// `node native/tests/ohos_channel_test.cjs` 覆盖——那是执行真实 ArkTS 代码，
/// 比在这里用 `contains('...')` 断言源码字符串有价值得多，所以本文件不再重复。
/// 真实原生执行证据在 `python_lifecycle_test.dart` 的 real MicroPython 组和
/// 主机 C VM 测试里；本文件不声称任何原生运行正确性。
void main() {
  final root = Directory.current.path;
  final template = File(p.join(root, 'native', 'ohos', 'QfliPyNative.ets'));
  final packaged = File(
    p.join(
      root,
      'ohos',
      'entry',
      'src',
      'main',
      'ets',
      'plugins',
      'QfliPyNative.ets',
    ),
  );

  test('两份 QfliPyNative.ets 副本逐字节相同', () {
    expect(
      template.existsSync(),
      isTrue,
      reason: '缺少 ArkTS 模板：${template.path}',
    );
    expect(
      packaged.existsSync(),
      isTrue,
      reason: '缺少进构建路径的 ArkTS：${packaged.path}',
    );
    final a = template.readAsBytesSync();
    final b = packaged.readAsBytesSync();
    expect(
      a.length,
      b.length,
      reason:
          '两份副本长度不同：${a.length} vs ${b.length}。'
          '改一份必须复制到另一份。',
    );
    expect(
      a,
      b,
      reason:
          '两份副本内容不同。native/ohos/ 那份不在构建路径，'
          '漂了不会有任何编译错误。',
    );
  });
}
