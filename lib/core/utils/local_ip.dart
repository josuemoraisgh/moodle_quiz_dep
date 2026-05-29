import 'dart:io';

import 'package:flutter/foundation.dart';

/// Descobre o IP local preferencial para servir a rede de alunos.
///
/// Prioridade: Ethernet (adaptador USB-C do S23) > Wi-Fi > qualquer IPv4 não-loopback.
/// Em plataforma web não se aplica — retorna null.
Future<String?> getLocalIp() async {
  if (kIsWeb) return null;

  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    // 1. Prefere interface com "eth" no nome (Ethernet via adaptador USB-C)
    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      if (name.contains('eth') ||
          name.contains('usb') ||
          name.contains('rndis')) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    }

    // 2. Fallback: Wi-Fi (wlan)
    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      if (name.contains('wlan') ||
          name.contains('wifi') ||
          name.contains('wi-fi')) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    }

    // 3. Qualquer outro IPv4 não-loopback
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
  } catch (_) {}

  return null;
}

/// Retorna todos os IPs locais disponíveis (para debug / listagem na UI).
Future<List<({String name, String ip})>> getAllLocalIps() async {
  if (kIsWeb) return [];
  final result = <({String name, String ip})>[];
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) {
          result.add((name: iface.name, ip: addr.address));
        }
      }
    }
  } catch (_) {}
  return result;
}

/// Detecta se o app web está rodando num IP de rede local.
/// Usado pelo Flutter Web para ativar o LocalStateClient automaticamente.
bool isLocalNetworkHost(String hostname) {
  if (hostname == 'localhost' || hostname == '127.0.0.1') return true;
  if (hostname.startsWith('192.168.')) return true;
  if (hostname.startsWith('10.')) return true;
  final parts = hostname.split('.');
  if (parts.length == 4) {
    final second = int.tryParse(parts[1]) ?? 256;
    if (parts[0] == '172' && second >= 16 && second <= 31) return true;
  }
  return false;
}
