import 'dart:async';

import 'package:nsd/nsd.dart';

class DiscoveryService {
  static const String serviceType = "_aerodrop._tcp";

  Registration? registration;
  Discovery? discovery;

  final StreamController<List<Service>> _discoverNodesController =
      StreamController.broadcast();

  Stream<List<Service>> get discoverNodesStream =>
      _discoverNodesController.stream;

  final List<Service> _currentNodes = [];

  String? _myDeviceName;

  Future<void> startBroadcasting({
    required String myDeviceName,
    required int port,
  }) async {
    _myDeviceName = myDeviceName;
    final service = Service(name: myDeviceName, port: port, type: serviceType);

    try {
      registration = await register(service);
      print("📡 AeroDrop: Broadcasting as '$myDeviceName' on port $port");
    } catch (e) {
      print("🚨 AeroDrop Error: Failed to broadcast - $e");
    }
  }

  Future<void> stopBroadcasting() async {
    if (registration != null) {
      await unregister(registration!);
      registration = null;
      print("📡 AeroDrop: Stopped broadcasting");
    }
  }

  Future<void> startDiscovering() async {
    print("🔍 AeroDrop: Scanning for nearby devices...");

    try {
      discovery = await startDiscovery(serviceType);

      discovery?.addListener(() {
        _currentNodes.clear();

        for (var service in discovery!.services) {
          if (service.name != null &&
              service.host != null &&
              service.name != _myDeviceName) {
            _currentNodes.add(service);
            print("🟢 Found Device: ${service.name} at IP: ${service.host}");
          }
        }

        _discoverNodesController.sink.add([..._currentNodes]);
      });
    } catch (e) {
      print("🚨 AeroDrop Error: Failed to start scanner - $e");
    }
  }

  Future<void> stopDiscovering() async {
    if (discovery != null) {
      await stopDiscovery(discovery!);
      discovery = null;
      print("🔍 AeroDrop: Stopped scanning");
    }
  }

  void dispose() {
    stopBroadcasting();
    stopDiscovering();
    _discoverNodesController.close();
  }
}
