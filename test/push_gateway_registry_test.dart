import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/push/push_gateway_registry.dart';

class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('未配置网关地址时不发请求', () async {
    final adapter = _FakeAdapter();
    final client = Dio()..httpClientAdapter = adapter;
    final registry = PushGatewayRegistry(client: client, baseUrl: '');

    expect(registry.enabled, isFalse);
    final ok = await registry.registerAlias(alias: 'u42@1', token: 'token');
    expect(ok, isFalse);
    expect(adapter.requests, isEmpty);
  });

  test('注册别名时带上 Bearer 头与别名信息', () async {
    final adapter = _FakeAdapter();
    final client = Dio()..httpClientAdapter = adapter;
    final registry = PushGatewayRegistry(
      client: client,
      baseUrl: 'https://push.example.com',
    );

    expect(registry.enabled, isTrue);
    final ok = await registry.registerAlias(
      alias: 'u42@1',
      token: 'token-42',
      platform: 'android',
      vendor: 'xiaomi',
    );

    expect(ok, isTrue);
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://push.example.com/v1/aliases');
    expect(request.headers['Authorization'], 'Bearer token-42');
    final data = request.data;
    final body = data is String
        ? jsonDecode(data) as Map<String, dynamic>
        : (data as Map).cast<String, dynamic>();
    expect(body['alias'], 'u42@1');
    expect(body['platform'], 'android');
    expect(body['vendor'], 'xiaomi');
  });

  test('解绑别名使用 DELETE', () async {
    final adapter = _FakeAdapter();
    final client = Dio()..httpClientAdapter = adapter;
    final registry = PushGatewayRegistry(
      client: client,
      baseUrl: 'https://push.example.com',
    );

    await registry.unregisterAlias(alias: 'u42@1', token: 'token-42');

    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, 'https://push.example.com/v1/aliases/u42@1');
  });

  test('网关不可用时不抛异常', () async {
    final client = Dio()
      ..httpClientAdapter = _ThrowingAdapter();
    final registry = PushGatewayRegistry(
      client: client,
      baseUrl: 'https://push.example.com',
    );

    final ok = await registry.registerAlias(alias: 'u42@1', token: 'token');
    expect(ok, isFalse);
  });
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
  }

  @override
  void close({bool force = false}) {}
}
