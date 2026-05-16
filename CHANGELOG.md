# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-beta.1-wip]

### Renamed

- Renamed from `dartastic_flutter_bloc_otel` to `dartastic_bloc_otel`
  to match the riverpod core/overlay pattern. The package only ever
  depended on `bloc` (the pure-Dart core that `flutter_bloc`
  re-exports); the `flutter_` prefix was misleading. A new slim
  Flutter overlay ships under the original
  `dartastic_flutter_bloc_otel` name for `flutter_bloc`-based apps.

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
- 1 LGTM integration test polls Tempo round-trip.
- Example app produces a single `run-scenarios` trace with 16
  spans across a Bloc-happy-path, Cubit-happy-path, and a
  Bloc-error scenario.
