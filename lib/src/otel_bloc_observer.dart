// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:bloc/bloc.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'bloc_semantics.dart';

/// OpenTelemetry instrumentation for `package:bloc` / `package:flutter_bloc`.
///
/// A `BlocObserver` that emits one short span per Bloc/Cubit
/// lifecycle event (`onCreate` / `onEvent` / `onTransition` /
/// `onChange` / `onError` / `onClose`). Each span carries the bloc's
/// runtime type and the state types before/after, so a trace
/// waterfall reads as a state-machine timeline.
///
/// Install once at startup:
///
/// ```dart
/// Bloc.observer = OTelBlocObserver();
/// ```
///
/// Or compose with other observers via `MultiBlocObserver`:
///
/// ```dart
/// Bloc.observer = MultiBlocObserver(
///   observers: [
///     MyExistingObserver(),
///     OTelBlocObserver(),
///   ],
/// );
/// ```
///
/// ## Span shape per hook
///
/// | Bloc kind | Hook | Span name | Status |
/// |---|---|---|---|
/// | Any | `onCreate` | `bloc.created:<name>` | unset |
/// | `Bloc` | `onEvent` | (no span — covered by `onTransition`) | — |
/// | `Bloc` | `onTransition` | `bloc.transition:<name>` | unset |
/// | `Cubit` | `onChange` | `bloc.change:<name>` | unset |
/// | `Bloc` | `onChange` | (suppressed — `onTransition` carries strictly more info) | — |
/// | Any | `onError` | `bloc.error:<name>` | Error + `recordException` |
/// | Any | `onClose` | `bloc.closed:<name>` | unset |
///
/// **Why `onChange` is suppressed for Blocs:** `bloc` fires `onChange`
/// followed by `onTransition` on every event-driven state update.
/// Emitting both would double-count. Cubits don't have events, so
/// only `onChange` fires for them.
final class OTelBlocObserver extends BlocObserver {
  /// Creates an observer.
  ///
  /// - [tracer] — defaults to
  ///   `OTel.tracerProvider().getTracer('otel_bloc')`.
  /// - [recordLifecycle] — emit spans for `onCreate` / `onClose`.
  ///   Defaults to `true`. Turn off in chatty apps with many
  ///   short-lived blocs.
  /// - [recordTransitions] — emit spans for `onTransition` (Bloc)
  ///   and `onChange` (Cubit). Defaults to `true`.
  /// - [recordEventValues] — when `true`, record `event.toString()`
  ///   on `transition` spans. Off by default because events often
  ///   carry user data.
  /// - [recordStateValues] — when `true`, record `state.toString()`
  ///   for before/after on `transition` / `change` spans. Off by
  ///   default; same reasoning as event values.
  /// - [valueAttributeMaxLength] — cap on any `toString()`-derived
  ///   attribute. Defaults to 256.
  OTelBlocObserver({
    Tracer? tracer,
    this.recordLifecycle = true,
    this.recordTransitions = true,
    this.recordEventValues = false,
    this.recordStateValues = false,
    this.valueAttributeMaxLength = 256,
  }) : _tracer = tracer ?? OTel.tracerProvider().getTracer('otel_bloc');

  final Tracer _tracer;

  /// Whether to emit spans on `onCreate` / `onClose`.
  final bool recordLifecycle;

  /// Whether to emit spans on `onTransition` / `onChange`.
  final bool recordTransitions;

  /// Whether to record `event.toString()` on transition spans.
  final bool recordEventValues;

  /// Whether to record `state.toString()` for state before/after.
  final bool recordStateValues;

  /// Maximum length of any `toString()`-derived attribute.
  final int valueAttributeMaxLength;

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    if (!recordLifecycle) return;
    final span = _startSpan(bloc, event: 'created');
    span.end();
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    if (!recordTransitions) return;
    final span = _startSpan(bloc, event: 'transition');
    final extras = <String, Object>{
      BlocSemantics.eventType.key: transition.event.runtimeType.toString(),
      BlocSemantics.stateBefore.key:
          transition.currentState.runtimeType.toString(),
      BlocSemantics.stateAfter.key: transition.nextState.runtimeType.toString(),
    };
    if (recordEventValues) {
      extras[BlocSemantics.eventValue.key] = _clip(transition.event.toString());
    }
    if (recordStateValues) {
      extras[BlocSemantics.stateBeforeValue.key] =
          _clip(transition.currentState.toString());
      extras[BlocSemantics.stateAfterValue.key] =
          _clip(transition.nextState.toString());
    }
    span.addAttributes(OTel.attributesFromMap(extras));
    span.end();
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    if (!recordTransitions) return;
    // For Blocs, onTransition fires immediately after onChange with
    // strictly more info (it includes the triggering event). Skip
    // the onChange span to avoid double-counting.
    if (bloc is Bloc) return;

    final span = _startSpan(bloc, event: 'change');
    final extras = <String, Object>{
      BlocSemantics.stateBefore.key: change.currentState.runtimeType.toString(),
      BlocSemantics.stateAfter.key: change.nextState.runtimeType.toString(),
    };
    if (recordStateValues) {
      extras[BlocSemantics.stateBeforeValue.key] =
          _clip(change.currentState.toString());
      extras[BlocSemantics.stateAfterValue.key] =
          _clip(change.nextState.toString());
    }
    span.addAttributes(OTel.attributesFromMap(extras));
    span.end();
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    final span = _startSpan(bloc, event: 'error');
    // Spec order: recordException first, THEN setStatus.
    span.recordException(error, stackTrace: stackTrace);
    span.setStatus(SpanStatusCode.Error, error.toString());
    span.end();
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);
    if (!recordLifecycle) return;
    final span = _startSpan(bloc, event: 'closed');
    span.end();
  }

  APISpan _startSpan(BlocBase<dynamic> bloc, {required String event}) {
    final name = bloc.runtimeType.toString();
    final attrs = <String, Object>{
      BlocSemantics.blocName.key: name,
      BlocSemantics.blocKind.key: bloc is Bloc ? 'Bloc' : 'Cubit',
      BlocSemantics.event.key: event,
    };
    return _tracer.startSpan(
      'bloc.$event:$name',
      attributes: OTel.attributesFromMap(attrs),
    );
  }

  String _clip(String s) {
    if (s.length <= valueAttributeMaxLength) return s;
    return '${s.substring(0, valueAttributeMaxLength)}…';
  }
}
