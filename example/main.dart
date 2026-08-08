// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// Minimal example: install the observer, drive a bloc through an event
/// inside an active span so the transition spans nest under it, then shut
/// down cleanly.
library;

import 'package:bloc/bloc.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_bloc/otel_bloc.dart';

/// Counter bloc: one event, one integer state.
final class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc() : super(0) {
    on<Increment>((event, emit) => emit(state + event.by));
  }
}

/// The only event [CounterBloc] handles.
final class Increment {
  const Increment(this.by);

  /// How much to add to the current count.
  final int by;
}

/// Marker type for [CounterBloc]'s event stream.
typedef CounterEvent = Increment;

Future<void> main() async {
  await OTel.initialize(
    serviceName: 'bloc-otel-example',
    serviceVersion: '0.0.1',
  );

  // One observer covers every bloc in the process. `recordEventValues` /
  // `recordStateValues` are off by default so payloads never land in
  // telemetry by accident; opt in only for non-sensitive blocs.
  Bloc.observer = OTelBlocObserver(recordTransitions: true);

  final bloc = CounterBloc();

  // Wrap the dispatch in a parent span so the transition spans have
  // somewhere to attach. In a Flutter app the parent is usually the
  // navigation or gesture span.
  await OTel.tracer().startActiveSpanAsync<void>(
    name: 'user taps +1',
    fn: (_) async {
      bloc.add(const Increment(1));
      // Let the event loop deliver the transition to the observer.
      await bloc.stream.first;
    },
  );

  print('count: ${bloc.state}');

  await bloc.close();
  await OTel.shutdown();
}
