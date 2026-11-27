import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredAdminEndpoint {
  final String serverId;
  final int port;
  final List<String> ips;
  final String networkMode;

  const DiscoveredAdminEndpoint({
    required this.serverId,
    required this.port,
    required this.ips,
    this.networkMode = 'primary_router',
  });

  List<String> get httpsUrls =>
      ips.map((ip) => 'https://$ip:$port').toList(growable: false);
}

/// UDP broadcast probe for LAN Admin POS discovery (hint only — TLS pin + server_id still enforced).
class LanDiscoveryClient {
  static const int discoveryPort = 45843;
  static const String discoverMagic = 'KASIRTOKO_DISCOVER';
  static const String responsePrefix = 'KASIRTOKO_HERE|';

  Future<List<DiscoveredAdminEndpoint>> discover({
    String expectedServerId = '',
    Duration timeout = const Duration(milliseconds: 1100),
    int portOverride = discoveryPort,
    List<InternetAddress> extraTargets = const [],
  }) async {
    RawDatagramSocket? socket;
    final byServer = <String, DiscoveredAdminEndpoint>{};

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final targets = <InternetAddress>{
        InternetAddress('255.255.255.255'),
        ...extraTargets,
      };
      try {
        final intfs = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
          includeLinkLocal: false,
        );
        for (final intf in intfs) {
          for (final addr in intf.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
              targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.1'));
            }
          }
        }
      } catch (_) {}

      final packet = utf8.encode(discoverMagic);
      for (final target in targets) {
        try {
          socket.send(packet, target, portOverride);
        } catch (_) {}
      }

      final completer = Completer<void>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      socket.listen((evt) {
        if (evt != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = socket?.receive()) != null) {
          try {
            final raw = utf8.decode(d!.data);
            if (!raw.startsWith(responsePrefix)) continue;
            final payload = jsonDecode(raw.substring(responsePrefix.length));
            if (payload is! Map) continue;
            final srvId = (payload['server_id'] ?? '').toString().trim();
            if (expectedServerId.isNotEmpty && srvId.isNotEmpty && srvId != expectedServerId) {
              continue;
            }
            final port = (payload['port'] as num?)?.toInt() ?? 8443;
            final ips = <String>{
              for (final ip in (payload['ips'] as List<dynamic>? ?? const []))
                if (ip.toString().trim().isNotEmpty) ip.toString().trim(),
              if (d.address.address.isNotEmpty) d.address.address,
            }.toList();
            final mode = (payload['network_mode'] ?? 'primary_router').toString();
            final key = '$srvId|$port';
            if (ips.isNotEmpty) {
              final existing = byServer[key];
              if (existing == null) {
                byServer[key] = DiscoveredAdminEndpoint(
                  serverId: srvId,
                  port: port,
                  ips: ips,
                  networkMode: mode,
                );
              } else {
                byServer[key] = DiscoveredAdminEndpoint(
                  serverId: srvId,
                  port: port,
                  ips: {...existing.ips, ...ips}.toList(),
                  networkMode: mode,
                );
              }
            }
          } catch (_) {}
        }
      });

      await completer.future;
      timer.cancel();
    } catch (_) {
      // Discovery failure must gracefully degrade to saved primary/backup endpoint probing.
    } finally {
      try {
        socket?.close();
      } catch (_) {}
    }

    return byServer.values.toList();
  }

  /// Derives probable gateway/hotspot host URLs from the device's active IPv4 subnets.
  Future<List<String>> inferSubnetGatewayUrls({int port = 8443}) async {
    final urls = <String>[];
    try {
      final intfs = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final intf in intfs) {
        for (final addr in intf.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final gw = 'https://${parts[0]}.${parts[1]}.${parts[2]}.1:$port';
            if (!urls.contains(gw)) urls.add(gw);
          }
        }
      }
    } catch (_) {}
    for (final common in const ['192.168.43.1', '192.168.137.1', '172.20.10.1']) {
      final url = 'https://$common:$port';
      if (!urls.contains(url)) urls.add(url);
    }
    return urls;
  }
}
