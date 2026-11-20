// The LR detail Freight card shows what the transporter is owed: freight minus
// advance (as Accounts and the MIS report do), not the backend `balance`
// column, which is total - advance with Vistar's margin folded into total.
import 'package:flutter_test/flutter_test.dart';
import 'package:lr_management/shared/models/lr_models.dart';

void main() {
  // LR/PUN/26-27/01851 (20 Nov 2026): freight 37,000, margin 4,000, advance
  // 33,000. The card showed Total 41,000 and Balance 8,000.
  const lr = FreightDetails(
    freight: 37000,
    vistarMargin: 4000,
    advance: 33000,
    total: 41000,
    balance: 8000,
  );

  test('transporter balance is freight minus advance', () {
    expect(lr.transporterBalance, 4000);
    expect(lr.balance, 8000, reason: 'the backend column is unchanged');
  });

  test('transporter total leaves the Vistar margin out', () {
    expect(lr.transporterTotal, 37000);
  });

  test('a fully paid LR owes nothing, never a negative balance', () {
    const paid = FreightDetails(freight: 37000, advance: 38000);
    expect(paid.transporterBalance, 0);
  });
}
