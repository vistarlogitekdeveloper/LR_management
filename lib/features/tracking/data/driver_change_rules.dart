import '../../../shared/models/driver.dart';
import '../../masters/utils/transporter_kyc.dart' show normalizeIndianMobile;

/// Drivers the operator may switch to, best matches first: everyone but the
/// current driver, filtered by name / mobile / licence. Pure, so it is tested.
List<Driver> changeDriverCandidates(
  List<Driver> all, {
  required String? currentDriverId,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  final digits = q.replaceAll(RegExp(r'\D'), '');
  final out =
      all.where((d) {
        if (d.id == currentDriverId) return false;
        if (q.isEmpty) return true;
        return d.name.toLowerCase().contains(q) ||
            d.licenseNo.toLowerCase().contains(q) ||
            (digits.length >= 3 &&
                d.mobile.replaceAll(RegExp(r'\D'), '').contains(digits));
      }).toList()..sort((a, b) {
        // Trackable first: the ones that cannot be picked are listed after,
        // only so their absence is explained.
        final ta = changeDriverBlocker(a) == null ? 0 : 1;
        final tb = changeDriverBlocker(b) == null ? 0 : 1;
        if (ta != tb) return ta - tb;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  return out;
}

/// Why [d] cannot take over the trip, or null when it can.
String? changeDriverBlocker(Driver d) => normalizeIndianMobile(d.mobile) == null
    ? (d.mobile.trim().isEmpty
          ? 'No mobile number — cannot be tracked'
          : 'Mobile ${d.mobile} is not a valid 10-digit number')
    : null;
