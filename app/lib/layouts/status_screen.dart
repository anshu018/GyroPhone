import 'dart:async';

import 'package:flutter/material.dart';

import '../hid/ds4_report.dart';
import '../hid/hid_bridge.dart';
import '../hid/hid_log.dart';

/// Temporary M1 status screen (docs/UIUX.md interim rule): the look is
/// deliberately minimal — this exists to prove the transport and to feed
/// sticks/buttons into a Windows tester. The real design pass happens before
/// M2's wheel screen. Landscape is enforced in the Android manifest.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key, required this.bridge});

  final HidBridge bridge;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  Ds4ReportState _input = Ds4ReportState.neutral;

  void _send(Ds4ReportState next) {
    setState(() => _input = next);
    unawaited(widget.bridge.sendState(next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.bridge.log,
          builder: (context, _) {
            final bridge = widget.bridge;
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusHeader(bridge: bridge),
                  const SizedBox(height: 8),
                  if (!bridge.state.isLinked) _PairingGuide(bridge: bridge),
                  Expanded(
                    child: Row(
                      children: [
                        _StickPad(
                          label: 'L',
                          onChanged: (dx, dy) => _send(_input.copyWith(
                            leftX: _axisByte(dx),
                            leftY: _axisByte(dy),
                          )),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _HoldButton(
                                    label: '△',
                                    active: _input.triangle,
                                    onChanged: (p) => _send(_input.copyWith(triangle: p)),
                                  ),
                                  _HoldButton(
                                    label: '○',
                                    active: _input.circle,
                                    onChanged: (p) => _send(_input.copyWith(circle: p)),
                                  ),
                                  _HoldButton(
                                    label: '✕',
                                    active: _input.cross,
                                    onChanged: (p) => _send(_input.copyWith(cross: p)),
                                  ),
                                  _HoldButton(
                                    label: '□',
                                    active: _input.square,
                                    onChanged: (p) => _send(_input.copyWith(square: p)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _HoldButton(
                                    label: 'L1',
                                    active: _input.l1,
                                    onChanged: (p) => _send(_input.copyWith(l1: p)),
                                  ),
                                  _HoldButton(
                                    label: 'R1',
                                    active: _input.r1,
                                    onChanged: (p) => _send(_input.copyWith(r1: p)),
                                  ),
                                  _HoldButton(
                                    label: 'SH',
                                    active: _input.share,
                                    onChanged: (p) => _send(_input.copyWith(share: p)),
                                  ),
                                  _HoldButton(
                                    label: 'OP',
                                    active: _input.options,
                                    onChanged: (p) => _send(_input.copyWith(options: p)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _StickPad(
                          label: 'R',
                          onChanged: (dx, dy) => _send(_input.copyWith(
                            rightX: _axisByte(dx),
                            rightY: _axisByte(dy),
                          )),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _LogTail(log: bridge.log),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Normalized axis position [-1, 1] → stick byte. DS4 convention: X is 0 at
  /// the left, Y is 0 at the TOP — dragging the pad up must decrease the byte,
  /// so Y keeps the caller's sign (the pad already reports negative dy for up).
  static int _axisByte(double normalized) =>
      (128 + (normalized.clamp(-1.0, 1.0) * 127)).round().clamp(0, 255);
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.bridge});

  final HidBridge bridge;

  @override
  Widget build(BuildContext context) {
    final stats = bridge.latencyStats;
    final subtitle = bridge.state.isLinked
        ? 'host: ${bridge.hostName ?? bridge.hostAddress ?? '?'} · latency: $stats'
        : 'not connected to a PC';
    return Row(
      children: [
        Chip(label: Text(bridge.state.name)),
        const SizedBox(width: 12),
        Expanded(child: Text(subtitle, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _PairingGuide extends StatelessWidget {
  const _PairingGuide({required this.bridge});

  final HidBridge bridge;

  @override
  Widget build(BuildContext context) {
    final needsEnable = bridge.state == HidState.uninitialized ||
        bridge.state == HidState.unregistered ||
        bridge.state == HidState.registering ||
        bridge.state == HidState.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pair from the PC:'),
            const Text('1. Keep this app open and the screen on.'),
            const Text('2. On the PC: Settings → Bluetooth → Add device.'),
            const Text('3. Pick this phone and accept the passkey on both ends.'),
            const Text('4. Open joy.cpl on the PC and move the pads below.'),
            if (needsEnable)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: bridge.start,
                  child: const Text('Enable controller mode'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogTail extends StatelessWidget {
  const _LogTail({required this.log});

  final HidLog log;

  @override
  Widget build(BuildContext context) {
    final lines = log.tail(4);
    return SizedBox(
      height: 72,
      child: SingleChildScrollView(
        child: Text(
          lines.map((e) => e.message).join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    );
  }
}

/// A draggable stick pad. Reports normalized offsets in [-1, 1] with the pad
/// center as origin, negative dy for up; snaps back to center on release.
class _StickPad extends StatefulWidget {
  const _StickPad({required this.label, required this.onChanged});

  final String label;
  final void Function(double dx, double dy) onChanged;

  @override
  State<_StickPad> createState() => _StickPadState();
}

class _StickPadState extends State<_StickPad> {
  Offset _normalized = Offset.zero;

  void _onPanUpdate(DragUpdateDetails details, double maxRadius) {
    setState(() {
      final next = _normalized + details.delta / maxRadius;
      // Clamp to the unit circle so the reported axis stays in range.
      final distance = next.distance;
      _normalized = distance <= 1 ? next : next / distance;
    });
    widget.onChanged(_normalized.dx, _normalized.dy);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxRadius = constraints.biggest.shortestSide / 2;
        return GestureDetector(
          onPanStart: (details) =>
              _onPanUpdate(DragUpdateDetails(globalPosition: details.globalPosition, localPosition: details.localPosition, delta: Offset.zero), maxRadius),
          onPanUpdate: (details) => _onPanUpdate(details, maxRadius),
          onPanEnd: (_) {
            setState(() => _normalized = Offset.zero);
            widget.onChanged(0, 0);
          },
          child: Container(
            width: maxRadius * 2,
            height: maxRadius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            alignment: Alignment.center,
            child: Transform.translate(
              offset: _normalized * maxRadius * 0.8,
              child: CircleAvatar(
                radius: maxRadius * 0.3,
                child: Text(widget.label),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HoldButton extends StatelessWidget {
  const _HoldButton({required this.label, required this.active, required this.onChanged});

  final String label;
  final bool active;
  final void Function(bool pressed) onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onChanged(true),
      onTapUp: (_) => onChanged(false),
      onTapCancel: () => onChanged(false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: active ? Colors.lightBlueAccent : Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label),
      ),
    );
  }
}
