import 'dart:async';

import 'package:flutter/material.dart';

import '../hid/hid_bridge.dart';

/// Connection sheet (M2 spec R8): live state, the proven first-time pairing
/// flow (in-app discoverable + PC steps — never removed, M1 spec task 11),
/// and the bonded-hosts Connect list. Look is temporary per the UIUX interim
/// rule.
class ConnectionSheet extends StatefulWidget {
  const ConnectionSheet({super.key, required this.bridge});

  final HidBridge bridge;

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  List<BondedHost> _hosts = [];
  bool _hostsLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHosts());
  }

  Future<void> _loadHosts() async {
    final hosts = await widget.bridge.bondedHosts();
    if (!mounted) return;
    setState(() {
      _hosts = hosts;
      _hostsLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bridge = widget.bridge;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${bridge.state.label}${bridge.hostName == null ? '' : ' · ${bridge.hostName}'}'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => unawaited(bridge.makeDiscoverable()),
            child: const Text('Make discoverable (5 min)'),
          ),
          const SizedBox(height: 12),
          const Text(
            'First time on this PC:\n'
            '1. Tap "Make discoverable" above (keep this app open).\n'
            '2. On the PC: Bluetooth settings → Add device → Wireless Controller.\n'
            '3. The chip on the wheel screen turns green when connected.',
          ),
          const Divider(height: 24),
          Text('Paired PCs', style: Theme.of(context).textTheme.titleSmall),
          if (_hostsLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            )
          else if (_hosts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('None yet — pair from the PC first.'),
            )
          else
            for (final host in _hosts)
              ListTile(
                dense: true,
                title: Text(host.name ?? host.address),
                subtitle: Text('${host.state} · ${host.address}'),
                trailing: host.state == 'connected'
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : IconButton(
                        icon: const Icon(Icons.link),
                        tooltip: 'Connect',
                        onPressed: host.state == 'disconnected'
                            ? () {
                                unawaited(bridge.connectTo(host.address));
                                unawaited(_loadHosts());
                              }
                            : null,
                      ),
              ),
          const Divider(height: 24),
          ValueListenableBuilder(
            valueListenable: bridge.wheelFrame,
            builder: (context, frame, _) => Text(frame.telemetryLabel),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
