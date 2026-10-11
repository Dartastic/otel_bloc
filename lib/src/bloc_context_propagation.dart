// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:collection';

import 'package:bloc/bloc.dart';
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

/// Wraps an [EventTransformer] so each event handler runs in the
/// OpenTelemetry [Context] that was current when the event was added.
///
/// `Bloc.add` runs in the caller's zone, but bloc invokes the handler
/// later, from a stream subscription that was listened to in the zone
/// where the bloc was *constructed* (usually app startup). Zone-based
/// context therefore does not follow the event: a span made current
/// around `bloc.add(...)` is not the parent of anything the handler
/// does. This transformer restores it, so the handler, everything it
/// awaits, the HTTP calls it makes and the observer's
/// `bloc.transition` span all nest under the caller's span.
///
/// It needs [OTelBlocObserver] installed as (or inside) `Bloc.observer`:
/// the observer's `onEvent` hook runs synchronously inside `add`, in
/// the caller's zone, and captures the context there.
///
/// Install once at startup, **before any bloc is constructed** (a bloc
/// reads `Bloc.transformer` in its constructor):
///
/// ```dart
/// Bloc.observer = OTelBlocObserver();
/// Bloc.transformer = otelContextTransformer(Bloc.transformer);
/// ```
///
/// Handlers that pass their own transformer wrap it the same way:
///
/// ```dart
/// on<Refresh>(_onRefresh, transformer: otelContextTransformer(droppable()));
/// ```
///
/// Events that are `null`, numbers, strings, booleans or records cannot
/// be tracked (Dart cannot attach data to them) and run in the handler's
/// own zone, as they would without this transformer.
EventTransformer<E> otelContextTransformer<E>(EventTransformer<E> inner) {
  return (events, mapper) => inner(
        // Claim each event's context as it leaves the bloc's event
        // stream, before `inner` can drop, debounce or queue it, so
        // events dropped by `inner` never leave a stale context behind.
        events.map((event) {
          _claim(event);
          return event;
        }),
        (event) {
          final context = _claimed(event);
          if (context == null) return mapper(event);
          // Bloc calls the handler synchronously from `mapper`, so the
          // whole handler, including its async continuations, inherits
          // the zone that `runSync` creates.
          return context.runSync(() => mapper(event));
        },
      );
}

/// Maximum contexts held per event instance. The same `const` event can
/// be added many times before delivery; past this many, the oldest is
/// discarded (its handler then runs without the caller's context).
const _maxPendingPerEvent = 64;

/// Contexts captured by `onEvent`, oldest first, keyed by event
/// identity. Weakly held, so entries go away with their events.
final _pending = Expando<Queue<Context>>('otel_bloc.pending');

/// The context claimed by the most recent delivery of each event
/// instance, read when the handler starts.
final _delivered = Expando<Context>('otel_bloc.delivered');

bool _isTrackable(Object? event) =>
    event != null &&
    event is! num &&
    event is! String &&
    event is! bool &&
    event is! Record;

/// Records [Context.current] for [event]. Called from
/// `OTelBlocObserver.onEvent`, which bloc runs inside `add`.
void captureEventContext(Object? event) {
  if (!_isTrackable(event)) return;
  final queue = _pending[event!] ??= Queue<Context>();
  if (queue.length >= _maxPendingPerEvent) queue.removeFirst();
  queue.addLast(Context.current);
}

void _claim(Object? event) {
  if (!_isTrackable(event)) return;
  final queue = _pending[event!];
  if (queue == null || queue.isEmpty) return;
  _delivered[event] = queue.removeFirst();
}

Context? _claimed(Object? event) =>
    _isTrackable(event) ? _delivered[event!] : null;
