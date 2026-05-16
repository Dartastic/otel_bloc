// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Integration test: drive a small Bloc + Cubit through the observer
/// against a real OTLP endpoint, then poll Tempo's HTTP API to
/// verify the spans arrived with the expected `bloc.*` semconv
/// attributes.
///
/// Skipped when no LGTM stack is reachable. Bring one up first:
///   docker compose -f tool/lgtm/docker-compose.yml up -d
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_bloc/otel_bloc.dart';
import 'package:test/test.dart';

const _defaultOtlp = 'http://localhost:4318';
const _defaultOtlpPort = 4318;
const _defaultTempo = 'http://localhost:3200';

void main() {
  group('LGTM end-to-end', () {
    final otlpEndpoint =
        Platform.environment['LGTM_OTLP_ENDPOINT'] ?? _defaultOtlp;
    final tempoUrl = Platform.environment['LGTM_TEMPO_URL'] ?? _defaultTempo;

    test('OTelBlocObserver spans appear in Tempo', () async {
      final tempoOk = await _tempoReachable(tempoUrl);
      final otlpOk = await _portOpen(otlpEndpoint);
      if (!tempoOk || !otlpOk) {
        markTestSkipped(
          'LGTM not reachable (tempo=$tempoOk otlp=$otlpOk) — start it '
          'with `docker compose -f tool/lgtm/docker-compose.yml up -d` and '
          'rerun.',
        );
        return;
      }

      await OTel.reset();
      await OTel.initialize(
        serviceName: 'bloc-otel-lgtm-itest',
        serviceVersion: '0.0.1',
        endpoint: otlpEndpoint,
      );
      Bloc.observer = OTelBlocObserver();

      late String traceIdHex;
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'itest-root',
        fn: (rootSpan) async {
          traceIdHex = rootSpan.spanContext.traceId.hexString;
          final bloc = _ItestBloc();
          bloc.add(const _ItestEvent());
          await Future<void>.delayed(Duration.zero);
          await bloc.close();
        },
      );

      Bloc.observer = const _NoopObserver();
      await OTel.tracerProvider().forceFlush();
      await OTel.shutdown();

      final trace = await _pollTempoForTrace(
        tempoUrl: tempoUrl,
        traceIdHex: traceIdHex,
        timeout: const Duration(seconds: 30),
      );
      expect(trace, isNotNull,
          reason: 'Tempo never returned trace $traceIdHex');

      final spans = <Map<String, dynamic>>[];
      for (final batch in (trace!['batches'] as List<dynamic>? ?? const [])) {
        final scopeSpans =
            (batch as Map<String, dynamic>)['scopeSpans'] as List<dynamic>? ??
                const [];
        for (final ss in scopeSpans) {
          final raw = (ss as Map<String, dynamic>)['spans'] as List<dynamic>? ??
              const [];
          for (final s in raw) {
            spans.add(s as Map<String, dynamic>);
          }
        }
      }
      expect(spans, isNotEmpty);

      final names = spans.map((s) => s['name'] as String).toSet();
      expect(names, contains('bloc.created:_ItestBloc'));
      expect(names, contains('bloc.transition:_ItestBloc'));
      expect(names, contains('bloc.closed:_ItestBloc'));

      final transition = spans.firstWhere(
        (s) => s['name'] == 'bloc.transition:_ItestBloc',
      );
      final attrKeys = <String>{
        for (final a in transition['attributes'] as List<dynamic>? ?? const [])
          (a as Map<String, dynamic>)['key'] as String,
      };
      expect(attrKeys, contains('bloc.name'));
      expect(attrKeys, contains('bloc.kind'));
      expect(attrKeys, contains('bloc.event.type'));
      expect(attrKeys, contains('bloc.state.before'));
      expect(attrKeys, contains('bloc.state.after'));
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}

class _ItestEvent {
  const _ItestEvent();
}

class _ItestBloc extends Bloc<_ItestEvent, int> {
  _ItestBloc() : super(0) {
    on<_ItestEvent>((event, emit) => emit(state + 1));
  }
}

final class _NoopObserver extends BlocObserver {
  const _NoopObserver();
}

Future<bool> _tempoReachable(String tempoUrl) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    final req = await c.getUrl(Uri.parse('$tempoUrl/ready'));
    final resp = await req.close().timeout(const Duration(seconds: 2));
    await resp.drain<void>();
    c.close();
    return resp.statusCode == 200;
  } on Exception {
    return false;
  }
}

Future<bool> _portOpen(String endpoint) async {
  try {
    final uri = Uri.parse(endpoint);
    final host = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = uri.hasPort ? uri.port : _defaultOtlpPort;
    final socket =
        await Socket.connect(host, port, timeout: const Duration(seconds: 1));
    socket.destroy();
    return true;
  } on Exception {
    return false;
  }
}

Future<Map<String, dynamic>?> _pollTempoForTrace({
  required String tempoUrl,
  required String traceIdHex,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  final client = HttpClient();
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final req = await client.getUrl(
          Uri.parse('$tempoUrl/api/traces/$traceIdHex'),
        );
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final parsed = jsonDecode(body) as Map<String, dynamic>;
          final batches = parsed['batches'] as List<dynamic>? ?? const [];
          if (batches.isNotEmpty) return parsed;
        } else {
          await resp.drain<void>();
        }
      } on Exception {
        // Transient — keep polling.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } finally {
    client.close();
  }
  return null;
}
