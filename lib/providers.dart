import 'package:aero_drop/tcp_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:nsd/nsd.dart';
import 'clipboard_service.dart';
import 'discovery_service.dart';

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

final discoveredNodesProvider = StreamProvider<List<Service>>((ref) {
  final service = ref.watch(discoveryServiceProvider);
  return service.discoverNodesStream;
});

final tcpServiceProvider = Provider<TcpService>((ref) {
  final tcpService = TcpService();

  ref.onDispose(() {
    tcpService.dispose();
  });

  return tcpService;
});

final incomingHandshakesProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final service = ref.watch(tcpServiceProvider);
  return service.incomingHandshakes;
});

final incomingClipBoardProvider = StreamProvider<String>((ref) {
  final service = ref.watch(tcpServiceProvider);
  return service.incomingClipboard;
});

final transferProgressProvider = StreamProvider<List<double?>>((ref) {
  final service = ref.watch(tcpServiceProvider);
  return service.transferProgress;
});

final activeFileNameProvider = StateProvider<List<String?>>((ref) => []);

final selectedDeviceIpProvider = StateProvider<String?>((ref) => null);
