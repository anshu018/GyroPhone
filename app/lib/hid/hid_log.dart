import 'dart:collection';

import 'package:flutter/foundation.dart';

enum HidLogKind { state, bluetooth, host, error }

/// One HID state-machine transition or platform event.
class HidLogEntry {
  const HidLogEntry(this.timestamp, this.kind, this.message);

  final DateTime timestamp;
  final HidLogKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Central logger for HID state transitions (CONVENTIONS.md bans scattered
/// debugPrint calls; report bytes are never logged — log spam hides real
/// signals).
///
/// The status screen shows the tail of the buffer; in debug builds errors are
/// additionally forwarded to the console.
class HidLog extends ChangeNotifier {
  /// Ring-buffer capacity; old entries are dropped from the head.
  static const int capacity = 200;

  final Queue<HidLogEntry> entries = ListQueue(capacity);

  void state(String message) => _add(HidLogKind.state, message);

  void bluetooth(String message) => _add(HidLogKind.bluetooth, message);

  void host(String message) => _add(HidLogKind.host, message);

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    final details = error == null ? '' : ' — $error';
    _add(HidLogKind.error, '$message$details');
    if (kDebugMode) {
      debugPrint('HidLog[error] $message$details');
      if (stackTrace != null) debugPrint('$stackTrace');
    }
  }

  /// The most recent [count] entries, oldest first.
  List<HidLogEntry> tail(int count) =>
      entries.length <= count ? entries.toList() : entries.skip(entries.length - count).toList();

  void _add(HidLogKind kind, String message) {
    if (entries.length == capacity) {
      entries.removeFirst();
    }
    entries.addLast(HidLogEntry(DateTime.now(), kind, message));
    notifyListeners();
  }
}
