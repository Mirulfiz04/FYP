import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/device_connection_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

const Color _accent = Color(0xFF6A5AE0);

/// Shows + manages the ESP32 heart-rate sensor connection. No live HR values
/// here — connectivity status only.
class ConnectedDevicesScreen extends StatefulWidget {
  const ConnectedDevicesScreen({super.key});

  @override
  State<ConnectedDevicesScreen> createState() => _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState extends State<ConnectedDevicesScreen> {
  final _ctrl = DeviceConnectionController();
  late final _addressCtrl = TextEditingController(text: _ctrl.address);

  @override
  void initState() {
    super.initState();
    _ctrl.loadLast();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  ({Color color, IconData icon, String label}) _status(DeviceConnState s) {
    return switch (s) {
      DeviceConnState.connected =>
        (color: MedsColors.greenDark, icon: Icons.check_circle, label: 'Connected'),
      DeviceConnState.connecting =>
        (color: MedsColors.amber, icon: Icons.sync, label: 'Connecting'),
      DeviceConnState.failed =>
        (color: MedsColors.red, icon: Icons.error, label: 'Connection Failed'),
      DeviceConnState.disconnected =>
        (color: MedsColors.muted, icon: Icons.bluetooth_disabled, label: 'Disconnected'),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connected Devices')),
      body: ListenableBuilder(
        listenable: _ctrl,
        builder: (context, _) {
          final st = _status(_ctrl.state);
          final connecting = _ctrl.state == DeviceConnState.connecting;
          final connected = _ctrl.state == DeviceConnState.connected;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(Icons.favorite, color: _accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_ctrl.deviceName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(_ctrl.connectionMethod,
                                  style: const TextStyle(
                                      color: MedsColors.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                        Pill(text: st.label, color: st.color, icon: st.icon),
                      ],
                    ),
                    const Divider(height: 24),
                    _info('Status', _ctrl.detail),
                    _info('Signal',
                        connected ? 'Reachable' : 'Not reachable'),
                    _info('Connection method', _ctrl.connectionMethod),
                    _info(
                      'Last connected',
                      _ctrl.lastConnected != null
                          ? DateFormat('dd MMM yyyy • HH:mm')
                              .format(_ctrl.lastConnected!.toLocal())
                          : 'Never',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader(
                title: 'Sensor address',
                icon: Icons.router_outlined,
                color: MedsColors.teal,
              ),
              AppCard(
                child: TextField(
                  controller: _addressCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Sensor IP or host',
                    hintText: '192.168.4.1',
                    prefixIcon: Icon(Icons.router_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: connecting
                      ? null
                      : () => _ctrl.connect(address: _addressCtrl.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: connecting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.wifi_tethering),
                  label: Text(connecting ? 'Connecting…' : 'Connect Device'),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: connecting ? null : _ctrl.retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: connected ? _ctrl.disconnect : null,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: MedsColors.red),
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Live heart-rate readings appear during an active session, not '
                'here.',
                style: TextStyle(color: MedsColors.muted, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(color: MedsColors.muted, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
