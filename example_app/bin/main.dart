// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Runnable demo of `otel_bloc` against a local LGTM stack.
///
/// Run the stack:
///   docker compose -f ../../../tool/lgtm/docker-compose.yml up -d
///
/// Then run this app:
///   dart run bin/main.dart
///
/// Open Grafana (http://localhost:3000), pick the Tempo datasource in
/// Explore, search for service `bloc-otel-example-app`. The
/// `run-scenarios` trace contains one short span per Bloc / Cubit
/// observer hook (created, transition, change, error, closed).
library;

import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
// Example apps use the Pro SDK to demonstrate the one-character
// switch (OTel.initialize -> DOTel.initialize). The package source
// still imports the OSS SDK directly so non-Pro users can use it.
import 'package:dartastic_opentelemetry_pro/dartastic_opentelemetry_pro.dart';
import 'package:otel_bloc/otel_bloc.dart';

const _serviceName = 'bloc-otel-example-app';
const _defaultEndpoint = 'http://localhost:4318';

Future<void> main(List<String> args) async {
  final endpoint =
      Platform.environment['OTEL_EXPORTER_OTLP_ENDPOINT'] ?? _defaultEndpoint;

  print('==> exporting to $endpoint as $_serviceName');

  await DOTel.initialize(
    serviceName: _serviceName,
    serviceVersion: '0.0.1',
    endpoint: endpoint,
  );

  // recordEventValues / recordStateValues on so the demo shows them.
  // Production apps should leave them off (events/state often carry
  // user data).
  Bloc.observer = OTelBlocObserver(
    recordEventValues: true,
    recordStateValues: true,
  );

  await DOTel.tracer().startActiveSpanAsync<void>(
    name: 'run-scenarios',
    fn: (_) async {
      await _scenario('bloc-happy-path', () async {
        final bloc = _CounterBloc();
        bloc.add(const _Increment());
        bloc.add(const _Increment());
        await Future<void>.delayed(Duration.zero);
        await bloc.close();
      });

      await _scenario('cubit-happy-path', () async {
        final cubit = _CounterCubit();
        cubit.increment();
        cubit.increment();
        cubit.increment();
        await Future<void>.delayed(Duration.zero);
        await cubit.close();
      });

      await _scenario('bloc-error', () async {
        await runZonedGuarded(() async {
          final bloc = _CounterBloc();
          bloc.add(const _Boom());
          await Future<void>.delayed(Duration.zero);
          await bloc.close();
        }, (e, _) {
          print('  caught: $e');
        });
      });
    },
  );

  print('==> flushing + shutting down');
  await DOTel.tracerProvider().forceFlush();
  await DOTel.shutdown();
  print('==> done. open Grafana at http://localhost:3000 → Explore → '
      'Tempo, service = $_serviceName');
}

Future<void> _scenario(String name, FutureOr<void> Function() body) async {
  print('--> $name');
  await DOTel.tracer().startActiveSpanAsync<void>(
    name: name,
    fn: (_) async {
      await body();
    },
  );
}

// --- Demo state machines ---

sealed class _CounterEvent {
  const _CounterEvent();
}

class _Increment extends _CounterEvent {
  const _Increment();
}

class _Boom extends _CounterEvent {
  const _Boom();
}

class _CounterBloc extends Bloc<_CounterEvent, int> {
  _CounterBloc() : super(0) {
    on<_Increment>((event, emit) => emit(state + 1));
    on<_Boom>((event, emit) {
      throw StateError('intentional demo failure');
    });
  }
}

class _CounterCubit extends Cubit<int> {
  _CounterCubit() : super(0);
  void increment() => emit(state + 1);
}
