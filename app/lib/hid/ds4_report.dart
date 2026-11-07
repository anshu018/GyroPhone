import 'dart:typed_data';

/// Hat switch direction, with wire values matching the DS4 encoding
/// (docs/specs/M1-pair-as-ds4.md R5): 0=N ... 7=NW, 8=released.
enum Ds4Hat {
  north(0),
  northEast(1),
  east(2),
  southEast(3),
  south(4),
  southWest(5),
  west(6),
  northWest(7),
  released(8);

  const Ds4Hat(this.wireValue);

  /// Value as encoded in the low nibble of byte 4.
  final int wireValue;
}

/// Full input state of the emulated controller. Immutable; the UI builds a
/// new instance per interaction and [Ds4ReportPacker] turns it into wire bytes.
///
/// Sticks and analog triggers are unsigned bytes centered at 128 (sticks) and
/// 0 (triggers), per the DS4 map.
class Ds4ReportState {
  const Ds4ReportState({
    this.leftX = 128,
    this.leftY = 128,
    this.rightX = 128,
    this.rightY = 128,
    this.hat = Ds4Hat.released,
    this.square = false,
    this.cross = false,
    this.circle = false,
    this.triangle = false,
    this.l1 = false,
    this.r1 = false,
    this.l2 = false,
    this.r2 = false,
    this.share = false,
    this.options = false,
    this.l3 = false,
    this.r3 = false,
    this.ps = false,
    this.touchpadClick = false,
    this.l2Analog = 0,
    this.r2Analog = 0,
  });

  static const neutral = Ds4ReportState();

  final int leftX;
  final int leftY;
  final int rightX;
  final int rightY;
  final Ds4Hat hat;
  final bool square;
  final bool cross;
  final bool circle;
  final bool triangle;
  final bool l1;
  final bool r1;
  final bool l2;
  final bool r2;
  final bool share;
  final bool options;
  final bool l3;
  final bool r3;
  final bool ps;
  final bool touchpadClick;
  final int l2Analog;
  final int r2Analog;

  /// Wire-relevant equality is the packer's byte-level dedupe below; it is
  /// strictly stronger than a field comparison (it also catches any drift
  /// between state and wire encoding).

  Ds4ReportState copyWith({
    int? leftX,
    int? leftY,
    int? rightX,
    int? rightY,
    Ds4Hat? hat,
    bool? square,
    bool? cross,
    bool? circle,
    bool? triangle,
    bool? l1,
    bool? r1,
    bool? l2,
    bool? r2,
    bool? share,
    bool? options,
    bool? l3,
    bool? r3,
    bool? ps,
    bool? touchpadClick,
    int? l2Analog,
    int? r2Analog,
  }) =>
      Ds4ReportState(
        leftX: leftX ?? this.leftX,
        leftY: leftY ?? this.leftY,
        rightX: rightX ?? this.rightX,
        rightY: rightY ?? this.rightY,
        hat: hat ?? this.hat,
        square: square ?? this.square,
        cross: cross ?? this.cross,
        circle: circle ?? this.circle,
        triangle: triangle ?? this.triangle,
        l1: l1 ?? this.l1,
        r1: r1 ?? this.r1,
        l2: l2 ?? this.l2,
        r2: r2 ?? this.r2,
        share: share ?? this.share,
        options: options ?? this.options,
        l3: l3 ?? this.l3,
        r3: r3 ?? this.r3,
        ps: ps ?? this.ps,
        touchpadClick: touchpadClick ?? this.touchpadClick,
        l2Analog: l2Analog ?? this.l2Analog,
        r2Analog: r2Analog ?? this.r2Analog,
      );
}

/// Packs [Ds4ReportState] into the 9-byte payload of input report 0x01
/// (docs/specs/M1-pair-as-ds4.md R5 for the byte map).
///
/// The packer owns the report counter (bits 2-7 of byte 6): it increments on
/// every report actually sent, and identical consecutive inputs are deduped so
/// the counter only advances on the wire, exactly like a real DS4 would.
///
/// No allocations: the caller provides the buffers, and they are reused.
class Ds4ReportPacker {
  /// Input report ID 0x01 — passed to the platform channel separately from
  /// the payload (Android's sendReport takes the ID as its own argument).
  static const int reportIdSmall = 0x01;

  static const int payloadSize = 9;

  int _counter = 0;

  // Candidate scratch (counter bits zeroed) vs last-sent scratch (also packed
  // with counter bits zeroed) — comparing them ignores the counter byte.
  final Uint8List _candidate = Uint8List(payloadSize);
  final Uint8List _lastSent = Uint8List(payloadSize);
  bool _hasLastSent = false;

  /// Forgets the last sent report so the next [packIfChanged] always packs.
  /// Call after a failed send — otherwise the dedupe believes that input was
  /// delivered, the host keeps the previous physical state, and returning to
  /// that exact input later would never be sent (stuck button/axis).
  void invalidateLastSent() {
    _hasLastSent = false;
  }

  /// Packs [state] into [out] (must be at least [payloadSize] bytes).
  /// Returns true when the input changed since the previous send and [out]
  /// now holds a fresh report; false means "no change, nothing to send".
  bool packIfChanged(Ds4ReportState state, Uint8List out) {
    _packInto(state, _candidate, 0);
    if (_hasLastSent && _bytesEqual(_candidate, _lastSent)) {
      return false;
    }
    _lastSent.setAll(0, _candidate);
    _hasLastSent = true;
    _packInto(state, out, ++_counter);
    return true;
  }

  void _packInto(Ds4ReportState s, Uint8List out, int counter) {
    out[0] = s.leftX;
    out[1] = s.leftY;
    out[2] = s.rightX;
    out[3] = s.rightY;
    out[4] = s.hat.wireValue |
        (s.square ? 0x10 : 0) |
        (s.cross ? 0x20 : 0) |
        (s.circle ? 0x40 : 0) |
        (s.triangle ? 0x80 : 0);
    out[5] = (s.l1 ? 0x01 : 0) |
        (s.r1 ? 0x02 : 0) |
        (s.l2 ? 0x04 : 0) |
        (s.r2 ? 0x08 : 0) |
        (s.share ? 0x10 : 0) |
        (s.options ? 0x20 : 0) |
        (s.l3 ? 0x40 : 0) |
        (s.r3 ? 0x80 : 0);
    out[6] = (s.ps ? 0x01 : 0) |
        (s.touchpadClick ? 0x02 : 0) |
        ((counter & 0x3F) << 2);
    out[7] = s.l2Analog;
    out[8] = s.r2Analog;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
