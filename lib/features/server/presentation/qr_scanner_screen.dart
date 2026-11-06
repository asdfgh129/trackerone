import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../domain/entities/server_profile.dart';

/// 解析服务器二维码。
///
/// 支持三种内容：
/// - `https://track.example.com`
/// - `{"name":"公司","url":"https://track.example.com","reportUrl":"..."}`
/// - `trackerone://server?url=https://track.example.com&name=公司`
abstract final class ServerProfileCodec {
  static ServerProfile parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FormatException('二维码内容为空');
    }

    if (value.startsWith('{')) {
      final decoded = jsonDecode(value);
      if (decoded is! Map) {
        throw const FormatException('二维码 JSON 格式不正确');
      }
      final map = decoded.cast<String, dynamic>();
      final address = (map['apiBaseUrl'] ??
              map['url'] ??
              map['server'] ??
              map['address']) as String?;
      if (address == null || address.isEmpty) {
        throw const FormatException('二维码缺少服务器地址');
      }
      return ServerProfile.fromInput(
        (map['name'] as String?) ?? '',
        address,
        reportUrl: map['reportUrl'] as String?,
        allowSelfSigned: map['allowSelfSigned'] as bool? ?? false,
      );
    }

    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'trackerone') {
      final params = uri.queryParameters;
      final address = params['url'] ?? params['server'] ?? params['address'];
      if (address == null || address.isEmpty) {
        throw const FormatException('二维码缺少服务器地址');
      }
      return ServerProfile.fromInput(
        params['name'] ?? '',
        address,
        reportUrl: params['reportUrl'],
        allowSelfSigned: params['allowSelfSigned'] == '1',
      );
    }

    return ServerProfile.fromInput('', value);
  }
}

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _handled = false;
  String? _error;
  MobileScannerController? _controller;

  MobileScannerController get _scanner =>
      _controller ??= MobileScannerController();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      _handled = true;
      try {
        final profile = ServerProfileCodec.parse(raw);
        Navigator.of(context).pop(profile);
      } on FormatException catch (error) {
        setState(() => _error = error.message);
        // 允许用户重新对准二维码。
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _handled = false);
        });
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('扫描服务器二维码')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '无法使用相机：${error.errorCode.name}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Card(
              color: theme.colorScheme.surface.withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error ?? '将服务器二维码放入取景框',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
