import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:gyrophone/hid/ds4_report.dart';

void main() {
  // Golden-byte tests: fixed inputs → exact wire bytes of input report 0x01
  // (byte map in docs/specs/M1-pair-as-ds4.md R5). The wire format is the
  // contract with the PC; these tests are its executable form.
  group('Ds4ReportPacker byte map', () {
    late Ds4ReportPacker packer;
    late Uint8List out;

    setUp(() {
      packer = Ds4ReportPacker();
      out = Uint8List(Ds4ReportPacker.payloadSize);
    });

    List<int> pack(Ds4ReportState state) {
      final changed = packer.packIfChanged(state, out);
      expect(changed, isTrue, reason: 'test states must differ from the previous one');
      return out.toList();
    }

    test('neutral input is centered sticks, released hat, no buttons', () {
      // Byte 6 carries counter 1: the packer increments before packing the
      // first report, exactly like a real DS4 counting its reports.
      expect(pack(Ds4ReportState.neutral), [
        128, 128, 128, 128, // sticks centered at 128
        0x08, // hat released (0x8), no face buttons
        0x00, // no L1..R3
        0x04, // no PS/touchpad, counter 1 (bits 2-7)
        0x00, 0x00, // triggers released
      ]);
    });

    test('byte 4 face buttons: square 0x10, cross 0x20, circle 0x40, triangle 0x80', () {
      expect(pack(Ds4ReportState.neutral.copyWith(square: true))[4], 0x08 | 0x10);
      expect(pack(Ds4ReportState.neutral.copyWith(cross: true))[4], 0x08 | 0x20);
      expect(pack(Ds4ReportState.neutral.copyWith(circle: true))[4], 0x08 | 0x40);
      expect(pack(Ds4ReportState.neutral.copyWith(triangle: true))[4], 0x08 | 0x80);
    });

    test('byte 4 low nibble: hat wire values, 8 = released', () {
      expect(pack(Ds4ReportState.neutral.copyWith(hat: Ds4Hat.north))[4], 0x00);
      expect(pack(Ds4ReportState.neutral.copyWith(hat: Ds4Hat.east))[4], 0x02);
      expect(pack(Ds4ReportState.neutral.copyWith(hat: Ds4Hat.southWest))[4], 0x05);
      expect(pack(Ds4ReportState.neutral.copyWith(hat: Ds4Hat.released))[4], 0x08);
    });

    test('byte 5: L1 R1 L2 R2 Share Options L3 R3 from bit 0 upward', () {
      expect(pack(Ds4ReportState.neutral.copyWith(l1: true))[5], 0x01);
      expect(pack(Ds4ReportState.neutral.copyWith(r1: true))[5], 0x02);
      expect(pack(Ds4ReportState.neutral.copyWith(l2: true))[5], 0x04);
      expect(pack(Ds4ReportState.neutral.copyWith(r2: true))[5], 0x08);
      expect(pack(Ds4ReportState.neutral.copyWith(share: true))[5], 0x10);
      expect(pack(Ds4ReportState.neutral.copyWith(options: true))[5], 0x20);
      expect(pack(Ds4ReportState.neutral.copyWith(l3: true))[5], 0x40);
      expect(pack(Ds4ReportState.neutral.copyWith(r3: true))[5], 0x80);
      expect(
        pack(Ds4ReportState.neutral.copyWith(l1: true, r3: true, options: true))[5],
        0x01 | 0x20 | 0x80,
      );
    });

    test('byte 6: PS is bit 0, touchpad bit 1, counter bits 2-7', () {
      // Mask off the counter bits; each pack() in this test is a fresh send.
      expect(pack(Ds4ReportState.neutral.copyWith(ps: true))[6] & 0x03, 0x01);
      expect(pack(Ds4ReportState.neutral.copyWith(touchpadClick: true))[6] & 0x03, 0x02);
      expect(pack(Ds4ReportState.neutral)[6] & 0x03, 0x00);
    });

    test('counter increments per sent report and wraps at 64', () {
      var state = Ds4ReportState.neutral;
      // First send: counter 1. Then flip a button 63 times → counter 64 ≡ 0.
      expect(pack(state)[6] >> 2, 1);
      for (var i = 0; i < 63; i++) {
        state = state.copyWith(cross: i.isEven);
        packer.packIfChanged(state, out);
      }
      expect(out[6] >> 2, 0, reason: 'counter wraps modulo 64');
    });

    test('byte order Y: 0 is up, 255 is down (DS4 convention)', () {
      expect(pack(Ds4ReportState.neutral.copyWith(leftY: 0))[1], 0);
      expect(pack(Ds4ReportState.neutral.copyWith(leftY: 255))[1], 255);
    });

    test('analog triggers ride bytes 7-8', () {
      final report = pack(Ds4ReportState.neutral.copyWith(l2Analog: 255, r2Analog: 128));
      expect(report[7], 255);
      expect(report[8], 128);
    });
  });

  group('Ds4ReportPacker dedupe', () {
    test('identical input is not re-packed', () {
      final packer = Ds4ReportPacker();
      final out = Uint8List(Ds4ReportPacker.payloadSize);
      expect(packer.packIfChanged(Ds4ReportState.neutral, out), isTrue);
      expect(packer.packIfChanged(Ds4ReportState.neutral, out), isFalse);
      expect(packer.packIfChanged(Ds4ReportState.neutral, out), isFalse);
      expect(packer.packIfChanged(Ds4ReportState.neutral.copyWith(cross: true), out), isTrue);
      expect(packer.packIfChanged(Ds4ReportState.neutral.copyWith(cross: true), out), isFalse);
    });

    test('sameInputAs ignores nothing wire-relevant', () {
      expect(
        Ds4ReportState.neutral.sameInputAs(Ds4ReportState.neutral.copyWith(l2Analog: 5)),
        isFalse,
      );
      expect(Ds4ReportState.neutral.sameInputAs(Ds4ReportState.neutral), isTrue);
    });
  });
}
