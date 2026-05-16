// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

/// Typed attribute keys for `package:bloc` / `package:flutter_bloc`
/// instrumentation.
///
/// No upstream OTel semantic convention exists for state-machine
/// frameworks; the `bloc.*` namespace is package-local pending a
/// proposal to the OTel client-side SIG. Stable across the 0.x line —
/// renaming a key is a breaking change.
enum BlocSemantics implements OTelSemantic {
  /// The bloc's `runtimeType` string (e.g., `CounterBloc`,
  /// `AuthCubit`). The natural identity for "which state machine".
  blocName('bloc.name'),

  /// `Bloc` or `Cubit`. Lets you slice metrics by kind.
  blocKind('bloc.kind'),

  /// Which observer hook fired —
  /// `created` / `event` / `transition` / `change` / `error` / `closed`.
  event('bloc.event'),

  /// The event's runtime type (e.g., `LoginRequested`). Only set on
  /// `transition` spans (Bloc-only).
  eventType('bloc.event.type'),

  /// The event's `toString()`, clipped. Only set when the observer
  /// is constructed with `recordEventValues: true`.
  eventValue('bloc.event.value'),

  /// The previous state's runtime type.
  stateBefore('bloc.state.before'),

  /// The next state's runtime type.
  stateAfter('bloc.state.after'),

  /// The previous state's `toString()`, clipped. Only set when the
  /// observer is constructed with `recordStateValues: true`.
  stateBeforeValue('bloc.state.before.value'),

  /// The next state's `toString()`, clipped. Only set when the
  /// observer is constructed with `recordStateValues: true`.
  stateAfterValue('bloc.state.after.value');

  const BlocSemantics(this.key);

  @override
  final String key;

  @override
  String toString() => key;
}
