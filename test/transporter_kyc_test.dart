// Aadhaar / contact-number rules for the transporter master.
//
// These MUST mirror LrmTransporter's isAadhaarNumber and isContactNumber
// validators on the server. A form that accepts something the server rejects
// loses the operator's work at the very end of the save, after they have
// already uploaded three documents.
import 'package:flutter_test/flutter_test.dart';

import 'package:lr_management/features/masters/utils/transporter_kyc.dart';

void main() {
  group('validateAadhaar', () {
    test('twelve digits is accepted', () {
      expect(validateAadhaar('123456789012'), isNull);
    });

    test('a number typed off the card, with spaces, is accepted', () {
      // People copy what is printed: "1234 5678 9012".
      expect(validateAadhaar('1234 5678 9012'), isNull);
      expect(validateAadhaar('1234-5678-9012'), isNull);
    });

    test('the wrong number of digits is refused', () {
      expect(validateAadhaar('12345'), 'Aadhaar must be 12 digits');
      expect(validateAadhaar('12345678901'), 'Aadhaar must be 12 digits');
      expect(validateAadhaar('1234567890123'), 'Aadhaar must be 12 digits');
    });

    test('letters are refused rather than silently stripped to nothing', () {
      expect(validateAadhaar('abcdefghijkl'), 'Aadhaar must be 12 digits');
    });

    test('an all-same-digit placeholder is refused', () {
      // What gets typed to get past a required field.
      expect(validateAadhaar('111111111111'), 'Not a valid Aadhaar');
      expect(validateAadhaar('000000000000'), 'Not a valid Aadhaar');
    });

    test(
      'blank is accepted — presence is the form\'s job, not this rule\'s',
      () {
        // Required when ADDING a transporter, optional when editing one that
        // predates the field, so the rule itself must not demand a value.
        expect(validateAadhaar(''), isNull);
        expect(validateAadhaar('   '), isNull);
        expect(validateAadhaar(null), isNull);
      },
    );
  });

  group('validateContactNumber', () {
    test('a plain ten-digit mobile is accepted', () {
      expect(validateContactNumber('9876543210'), isNull);
    });

    test('the shapes numbers get pasted in are accepted', () {
      for (final v in [
        '+91 98765 43210',
        '+919876543210',
        '098765-43210',
        '91 9876543210',
        '98765 43210',
      ]) {
        expect(validateContactNumber(v), isNull, reason: v);
      }
    });

    test('too few or too many digits are refused', () {
      expect(validateContactNumber('12345'), 'Enter a 10-digit mobile number');
      expect(
        validateContactNumber('987654321'),
        'Enter a 10-digit mobile number',
      );
      expect(
        validateContactNumber('98765432101'),
        'Enter a 10-digit mobile number',
      );
    });

    test('blank is accepted, for the same reason as Aadhaar', () {
      expect(validateContactNumber(''), isNull);
      expect(validateContactNumber('   '), isNull);
      expect(validateContactNumber(null), isNull);
    });

    test('letters are refused, not read as an empty field', () {
      // The field's own required check cannot catch this — the box is not
      // empty — so the rule has to.
      expect(
        validateContactNumber('call me'),
        'Enter a 10-digit mobile number',
      );
    });
  });

  group('digitsOnly', () {
    test('keeps only digits, so the stored value matches the column', () {
      expect(digitsOnly('1234 5678 9012'), '123456789012');
      expect(digitsOnly('+91 98765-43210'), '919876543210');
      expect(digitsOnly(''), '');
      expect(digitsOnly(null), '');
    });
  });
}
