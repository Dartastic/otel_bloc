// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_bloc/otel_bloc.dart';
import 'package:test/test.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;

  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

Map<String, Object> _attrs(Span span) =>
    {for (final a in span.attributes.toList()) a.key: a.value};

// --- Tiny Bloc and Cubit fixtures for tests ---

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
      throw StateError('boom');
    });
  }
}

class _CounterCubit extends Cubit<int> {
  _CounterCubit() : super(0);
  void increment() => emit(state + 1);
}

void main() {
  group('OTelBlocObserver', () {
    late _MemorySpanExporter exporter;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'bloc-otel-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
      Bloc.observer = OTelBlocObserver();
    });

    tearDown(() async {
      Bloc.observer = const _NoopObserver();
      await OTel.shutdown();
      await OTel.reset();
    });

    test('Bloc.add emits onCreate, onTransition, onClose spans', () async {
      final bloc = _CounterBloc();
      bloc.add(const _Increment());
      await Future<void>.delayed(Duration.zero);
      await bloc.close();

      final names = exporter.spans.map((s) => s.name).toList();
      expect(names, contains('bloc.created:_CounterBloc'));
      expect(names, contains('bloc.transition:_CounterBloc'));
      expect(names, contains('bloc.closed:_CounterBloc'));

      // onChange is suppressed for Blocs — only the transition span.
      expect(
        names.where((n) => n == 'bloc.change:_CounterBloc'),
        isEmpty,
        reason: 'onChange should be suppressed when onTransition fires',
      );

      final transition = exporter.spans
          .firstWhere((s) => s.name == 'bloc.transition:_CounterBloc');
      final attrs = _attrs(transition);
      expect(attrs['bloc.name'], equals('_CounterBloc'));
      expect(attrs['bloc.kind'], equals('Bloc'));
      expect(attrs['bloc.event'], equals('transition'));
      expect(attrs['bloc.event.type'], equals('_Increment'));
      expect(attrs['bloc.state.before'], equals('int'));
      expect(attrs['bloc.state.after'], equals('int'));
      // Value attributes are opt-in.
      expect(attrs.containsKey('bloc.event.value'), isFalse);
      expect(attrs.containsKey('bloc.state.before.value'), isFalse);
    });

    test('Cubit emit emits an onChange span (not onTransition)', () async {
      final cubit = _CounterCubit();
      cubit.increment();
      await Future<void>.delayed(Duration.zero);
      await cubit.close();

      final names = exporter.spans.map((s) => s.name).toList();
      expect(names, contains('bloc.created:_CounterCubit'));
      expect(names, contains('bloc.change:_CounterCubit'));
      expect(names, contains('bloc.closed:_CounterCubit'));
      // Cubits never produce transition spans.
      expect(names.where((n) => n.startsWith('bloc.transition:')), isEmpty);

      final change = exporter.spans
          .firstWhere((s) => s.name == 'bloc.change:_CounterCubit');
      expect(_attrs(change)['bloc.kind'], equals('Cubit'));
    });

    test('onError emits an error span with status=Error + exception event',
        () async {
      // Bloc routes errors thrown inside event handlers through
      // both `onError` AND the surrounding `Zone.handleUncaughtError`.
      // Run inside a guarded zone so the test runner doesn't mark
      // the test failed when bloc rethrows.
      await runZonedGuarded(() async {
        final bloc = _CounterBloc();
        bloc.add(const _Boom());
        await Future<void>.delayed(Duration.zero);
        await bloc.close();
      }, (_, __) {
        // Swallowed — we asserted via the exporter below.
      });

      final errSpan = exporter.spans.firstWhere(
        (s) => s.name == 'bloc.error:_CounterBloc',
      );
      expect(errSpan.status, equals(SpanStatusCode.Error));
      final events = errSpan.spanEvents ?? [];
      expect(events.any((e) => e.name == 'exception'), isTrue);
    });

    test('recordEventValues + recordStateValues capture clipped toString',
        () async {
      Bloc.observer = OTelBlocObserver(
        recordEventValues: true,
        recordStateValues: true,
        valueAttributeMaxLength: 4,
      );

      final bloc = _CounterBloc();
      bloc.add(const _Increment());
      await Future<void>.delayed(Duration.zero);
      await bloc.close();

      final transition = exporter.spans
          .firstWhere((s) => s.name == 'bloc.transition:_CounterBloc');
      final attrs = _attrs(transition);
      // Event value is clipped: the `_Increment` instance's
      // toString is `Instance of '_Increment'` (well over 4 chars),
      // so it ends with the ellipsis at length 5 (4 chars + '…').
      final eventValue = attrs['bloc.event.value']! as String;
      expect(eventValue, endsWith('…'));
      expect(eventValue.length, equals(5));
      // State values are short ints ('0' and '1' — under the cap)
      // so they pass through unclipped, but they're present.
      expect(attrs['bloc.state.before.value'], equals('0'));
      expect(attrs['bloc.state.after.value'], equals('1'));
    });

    test('recordLifecycle: false suppresses onCreate / onClose spans',
        () async {
      Bloc.observer = OTelBlocObserver(recordLifecycle: false);

      final bloc = _CounterBloc();
      bloc.add(const _Increment());
      await Future<void>.delayed(Duration.zero);
      await bloc.close();

      final names = exporter.spans.map((s) => s.name).toList();
      expect(names.where((n) => n.startsWith('bloc.created:')), isEmpty);
      expect(names.where((n) => n.startsWith('bloc.closed:')), isEmpty);
      // Transition span still there.
      expect(names, contains('bloc.transition:_CounterBloc'));
    });

    test('recordTransitions: false suppresses transition / change spans',
        () async {
      Bloc.observer = OTelBlocObserver(recordTransitions: false);

      final bloc = _CounterBloc();
      bloc.add(const _Increment());
      await Future<void>.delayed(Duration.zero);
      await bloc.close();

      final names = exporter.spans.map((s) => s.name).toList();
      expect(names.where((n) => n.startsWith('bloc.transition:')), isEmpty);
      expect(names.where((n) => n.startsWith('bloc.change:')), isEmpty);
      // Lifecycle spans still there.
      expect(names, contains('bloc.created:_CounterBloc'));
      expect(names, contains('bloc.closed:_CounterBloc'));
    });
  });
}

/// Restored as the global observer between tests so a misconfigured
/// observer from one test can't leak into the next via Bloc.observer.
final class _NoopObserver extends BlocObserver {
  const _NoopObserver();
}
