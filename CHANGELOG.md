# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0-wip]

## [0.2.0] - 2026-08-08

### Changed

- Dependency floors raised to `dartastic_opentelemetry ^1.1.0-beta.12` and
  `dartastic_opentelemetry_api ^1.0.0-rc.1`. The previous floors declared
  compatibility with API versions that predate the semconv enums this
  package uses and could not actually resolve-and-compile.
- `repository` URL corrected to the canonical `Dartastic` org casing so
  pub.dev repository verification succeeds.

### Renamed

- Ships as `otel_bloc`, the pure-Dart core, matching the core/overlay
  pattern. The package only ever depended on `bloc` (the pure-Dart
  core that `flutter_bloc` re-exports), so it works for both bloc and
  `flutter_bloc` apps. A slim Flutter overlay ships separately as
  `otel_flutter_bloc` for `flutter_bloc`-based apps.

### Added

- `OTelBlocObserver` — a `BlocObserver` that emits one short span
  per Bloc/Cubit lifecycle event (`onCreate`, `onTransition` for
  Bloc, `onChange` for Cubit, `onError`, `onClose`). Each span
  carries the `bloc.*` semconv attributes (bloc name + kind, event
  type, state before/after).
- `onChange` is suppressed for `Bloc`s because `onTransition` fires
  immediately after it with strictly more info. Cubits get their
  own `onChange` spans since they don't go through events.
- `onError` is recorded via `recordException` then `setStatus(Error)`,
  in OTel-spec order.
- `BlocSemantics` — typed attribute-key enum implementing
  `OTelSemantic`, package-local because OTel has no upstream
  semantic convention for state-machine frameworks yet.
- Constructor flags: `recordLifecycle` (default `true`),
  `recordTransitions` (default `true`), `recordEventValues`
  (default `false`), `recordStateValues` (default `false`),
  `valueAttributeMaxLength` (default 256).
- Targets `bloc: ^9.0.0`. Works with both `flutter_bloc` apps
  (which re-export `bloc`) and pure-Dart `bloc` apps.
- 6 unit tests covering: Bloc add → onCreate + onTransition +
  onClose (with onChange correctly suppressed), Cubit emit →
  onChange (with onTransition correctly absent), onError → Error
  status + exception event, recordEventValues + recordStateValues
  clipping, recordLifecycle false, recordTransitions false.
- 1 optional integration test verifies the OTLP export round-trip
  against a local trace backend; it self-skips when no local stack
  is reachable.
- Runnable `example/main.dart` drives a bloc through an event inside
  an active parent span so the transition spans nest under it.
