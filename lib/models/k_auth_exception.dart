class KAuthException implements Exception {
  final String message;
  final dynamic originalException;

  KAuthException(this.message, [this.originalException]);

  @override
  String toString() => "KAuthException: $message";
}

class KAuthNetworkException extends KAuthException {
  KAuthNetworkException(String message, [dynamic originalException])
      : super(message, originalException);
      
  @override
  String toString() => "KAuthNetworkException: $message";
}

class KAuthServerException extends KAuthException {
  final int? statusCode;
  
  KAuthServerException(String message, {this.statusCode, dynamic originalException})
      : super(message, originalException);

  @override
  String toString() => "KAuthServerException: $message (Status: $statusCode)";
}

class KAuthInvalidOtpException extends KAuthException {
  KAuthInvalidOtpException(String message) : super(message);
  
  @override
  String toString() => "KAuthInvalidOtpException: $message";
}
