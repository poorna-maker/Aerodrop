class PeerDevice {
  final String id;
  final String name;
  final String ip;
  final DateTime lastSeen;

  PeerDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.lastSeen,
  });

  PeerDevice copyWith({
    String? id,
    String? name,
    String? ip,
    DateTime? lastSeen,
  }) {
    return PeerDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
