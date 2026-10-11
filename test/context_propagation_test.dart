// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_bloc/otel_bloc.dart';
import 'package:test/test.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];

  @override
  Future<void> export(List<Span> s) async => spans.addAll(s);

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {}
}

/// Parent span id of every span the handlers started, in handler order.
final _handlerParents = <String?>[];

void _recordHandlerSpan(String name) {
  final span = OTel.tracerProvider().getTracer('test').startSpan(name);
  _handlerParents.add(span.parentSpanContext?.spanId.toString());
  span.end();
}

final class _Go {
  const _Go();
}

/// Starts a span before and after an await, then emits.
final class _GoBloc extends Bloc<_Go, int> {
  _GoBloc({EventTransformer<_Go>? transformer}) : super(0) {
    on<_Go>(
      (event, emit) async {
        _recordHandlerSpan('handler.sync');
        await Future<void>.delayed(Duration.zero);
        _recordHandlerSpan('handler.afterAwait');
        emit(state + 1);
      },
      transformer: transformer,
    );
  }
}

/// Handler that parks on [gate] so a droppable transformer drops
/// whatever arrives meanwhile.
final class _GatedBloc extends Bloc<_Go, int> {
  _GatedBloc(this.gate, EventTransformer<_Go> transformer) : super(0) {
    on<_Go>(
      (event, emit) async {
        _recordHandlerSpan('handler');
        await gate();
        emit(state + 1);
      },
      transformer: transformer,
    );
  }

  final Future<void> Function() gate;
}

/// Events are ints, which cannot carry a captured context.
final class _IntBloc extends Bloc<int, int> {
  _IntBloc() : super(0) {
    on<int>((event, emit) {
      _recordHandlerSpan('handler.int');
      emit(state + event);
    });
  }
}

/// Minimal `droppable()`: ignores events while a handler is running.
EventTransformer<E> _droppable<E>() => (events, mapper) => Stream<E>.multi(
      (controller) {
        var busy = false;
        final subscription = events.listen((event) {
          if (busy) return;
          busy = true;
          mapper(event).listen(
            controller.add,
            onError: controller.addError,
            onDone: () => busy = false,
          );
        }, onDone: controller.close);
        controller.onCancel = subscription.cancel;
      },
    );

void main() {
  group('otelContextTransformer', () {
    late _MemorySpanExporter exporter;
    late EventTransformer<dynamic> originalTransformer;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'bloc-context-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
      _handlerParents.clear();
      originalTransformer = Bloc.transformer;
      Bloc.observer = OTelBlocObserver(recordLifecycle: false);
      Bloc.transformer = otelContextTransformer(originalTransformer);
    });

    tearDown(() async {
      Bloc.transformer = originalTransformer;
      Bloc.observer = const _NoopObserver();
      await OTel.shutdown();
      await OTel.reset();
    });

    /// Runs [body] with a fresh span current, the way a tap handler
    /// does, and returns that span's id.
    String inSpan(String name, void Function() body) {
      final span = OTel.tracerProvider().getTracer('test').startSpan(name);
      Context.current.withSpan(span).runSync(body);
      span.end();
      return span.spanContext.spanId.toString();
    }

    String? parentOf(String spanName) => exporter.spans
        .lastWhere((s) => s.name == spanName)
        .parentSpanContext
        ?.spanId
        .toString();

    test('handler spans and the transition span parent to the add() caller',
        () async {
      // Constructed outside any span, like a bloc created at startup.
      final bloc = _GoBloc();
      final tapId = inSpan('tap', () => bloc.add(const _Go()));
      await bloc.stream.first;
      await bloc.close();

      expect(_handlerParents, [tapId, tapId]);
      expect(parentOf('bloc.transition:_GoBloc'), tapId);
    });

    test('without the transformer the handler loses the caller context',
        () async {
      // Proves the test above can fail: this is bloc's own behavior.
      Bloc.transformer = originalTransformer;
      final bloc = _GoBloc();
      final tapId = inSpan('tap', () => bloc.add(const _Go()));
      await bloc.stream.first;
      await bloc.close();

      expect(_handlerParents, everyElement(isNot(tapId)));
      expect(parentOf('bloc.transition:_GoBloc'), isNot(tapId));
    });

    test('propagateContext: false turns capture off', () async {
      Bloc.observer = OTelBlocObserver(propagateContext: false);
      final bloc = _GoBloc();
      final tapId = inSpan('tap', () => bloc.add(const _Go()));
      await bloc.stream.first;
      await bloc.close();

      expect(_handlerParents, everyElement(isNot(tapId)));
    });

    test('the same const event added from two callers keeps each context',
        () async {
      final bloc = _GoBloc();
      final first = inSpan('tap1', () => bloc.add(const _Go()));
      final second = inSpan('tap2', () => bloc.add(const _Go()));
      await bloc.stream.take(2).toList();
      await bloc.close();

      // The default transformer runs both handlers concurrently, so
      // their spans interleave: sync1, sync2, afterAwait1, afterAwait2.
      expect(_handlerParents, [first, second, first, second]);
    });

    test('an event dropped by a wrapped transformer leaves no stale context',
        () async {
      var gate = Completer<void>();
      final bloc = _GatedBloc(
        () => gate.future,
        otelContextTransformer(_droppable()),
      );

      final first = inSpan('tap1', () => bloc.add(const _Go()));
      await Future<void>.delayed(Duration.zero);
      // Dropped: the first handler is still parked on the gate.
      inSpan('tap2', () => bloc.add(const _Go()));
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await bloc.stream.first;

      gate = Completer<void>()..complete();
      final third = inSpan('tap3', () => bloc.add(const _Go()));
      await bloc.stream.first;
      await bloc.close();

      expect(_handlerParents, [first, third]);
    });

    test('untrackable events still run, without propagation', () async {
      final bloc = _IntBloc();
      inSpan('tap', () => bloc.add(1));
      await bloc.stream.first;
      await bloc.close();

      expect(bloc.state, 1);
      expect(_handlerParents, hasLength(1));
    });
  });
}

final class _NoopObserver extends BlocObserver {
  const _NoopObserver();
}
