/// Operations using the application's single embedded Python VM.
enum PythonRuntimeOperation { run, compile, analysis, debug }

/// An app-isolate gate shared by terminal, tools and editor runner instances.
///
/// Acquisition never queues work. The native mutex remains the final authority
/// for callers outside this isolate; this gate prevents obsolete editor checks
/// from being submitted behind a running user program.
class PythonRuntimeActivity {
  PythonRuntimeActivity();

  static final PythonRuntimeActivity shared = PythonRuntimeActivity();

  PythonRuntimeLease? _active;

  PythonRuntimeOperation? get operation => _active?.operation;
  bool get isBusy => _active != null;

  String get busyReason => switch (operation) {
    PythonRuntimeOperation.run => 'Python 程序正在运行，请停止或等待运行结束后重试。',
    PythonRuntimeOperation.compile => 'Python 正在编译，请稍后重试。',
    PythonRuntimeOperation.analysis => 'Python 正在检查其他源码，请稍后重试。',
    PythonRuntimeOperation.debug => 'Python 调试会话正在使用运行组件，请结束调试后重试。',
    null => '',
  };

  PythonRuntimeLease? tryAcquire(PythonRuntimeOperation operation) {
    if (_active != null) return null;
    return _active = PythonRuntimeLease._(this, operation);
  }
}

/// Retain this lease until the actual backend completion, including after stop.
class PythonRuntimeLease {
  PythonRuntimeLease._(this._activity, this.operation);

  final PythonRuntimeActivity _activity;
  final PythonRuntimeOperation operation;

  void release() {
    if (identical(_activity._active, this)) _activity._active = null;
  }
}
