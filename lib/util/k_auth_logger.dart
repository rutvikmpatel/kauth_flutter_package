import 'dart:developer' as developer;

class KAuthLogger {
  static void Function(String message)? _loggerCallback;
  static bool _enabled = true;

  static void setLogger(void Function(String message) callback) {
    _loggerCallback = callback;
  }

  static void enable(bool enabled) {
    _enabled = enabled;
  }

  static void log(String message, {String name = 'KAuth'}) {
    if (!_enabled) return;
    
    if (_loggerCallback != null) {
      _loggerCallback!("[$name] $message");
    } else {
      developer.log(message, name: name);
    }
  }
  
  static void error(String message, {Object? error, StackTrace? stackTrace, String name = 'KAuth'}) {
    if (!_enabled) return;
     if (_loggerCallback != null) {
      _loggerCallback!("[$name] ERROR: $message $error");
    } else {
      developer.log(message, name: name, error: error, stackTrace: stackTrace, level: 1000);
    }
  }
}
