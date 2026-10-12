/// The answer of GET /lrs/number-check: whether a manual LR number may be
/// used, and the number as the server would store it.
class LrNumberCheck {
  final String? number;
  final bool available;
  final String? code;
  final String? message;

  const LrNumberCheck({
    this.number,
    this.available = false,
    this.code,
    this.message,
  });

  factory LrNumberCheck.fromJson(Map<String, dynamic> j) => LrNumberCheck(
    number: j['number'] as String?,
    available: j['available'] == true,
    code: j['code'] as String?,
    message: j['message'] as String?,
  );
}
