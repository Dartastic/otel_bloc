# otel_bloc

OpenTelemetry instrumentation for [`package:bloc`](https://pub.dev/packages/bloc),
built on the [Dartastic OpenTelemetry SDK](https://pub.dev/packages/dartastic_opentelemetry).

Install one `BlocObserver` and every bloc / cubit lifecycle event
emits a short span — created, transition, change, error, closed —
turning your Tempo trace view into a state-machine timeline.

```dart
Bloc.observer = OTelBlocObserver();
```

Works for **both** pure-Dart `package:bloc` apps and
`package:flutter_bloc` apps. `flutter_bloc` re-exports `bloc`, so
the same observer attaches in either case. Flutter apps may prefer
`otel_flutter_bloc` (the matching Flutter overlay) to
get the `flutter_bloc` dependency wired in one step.

## Why

Bloc is the workhorse state-machine pattern in production Flutter
apps. Production bugs that only show up under specific
event-to-state sequences are exactly the bugs that traces solve —
but only if you can see the events and the transitions. This
package emits a span per observer hook, so Tempo's waterfall view
shows you the exact sequence that led to a bad state, ordered and
timestamped, with the triggering event captured.

The integration is **opt-in**: the OTel SDK does not depend on
`bloc`. Add this package only when you want it.

## Usage

```dart
import 'package:bloc/bloc.dart';
import 'package:otel_bloc/otel_bloc.dart';
import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

Future<void> main() async {
  await OTel.initialize(serviceName: 'my-app');
  Bloc.observer = OTelBlocObserver();

  // ...your bloc/cubit-using app...

  await OTel.shutdown();
}
```

To compose with other observers, use `MultiBlocObserver`:

```dart
Bloc.observer = MultiBlocObserver(
  observers: [
    MyExistingObserver(),   // sees events first
    OTelBlocObserver(),
  ],
);
```

## Span shape

| Bloc kind | Hook | Span name | Status |
|---|---|---|---|
| Any | `onCreate` | `bloc.created:<name>` | unset |
| `Bloc` | `onTransition` | `bloc.transition:<name>` | unset |
| `Cubit` | `onChange` | `bloc.change:<name>` | unset |
| Any | `onError` | `bloc.error:<name>` | Error + `recordException` |
| Any | `onClose` | `bloc.closed:<name>` | unset |

`onChange` is suppressed for `Bloc`s because `onTransition` fires
right after it with strictly more info (the triggering event).
Cubits don't have events, so only `onChange` fires for them.

| Attribute | Source | When set |
|---|---|---|
| `bloc.name` | `bloc.runtimeType` | every span |
| `bloc.kind` | `Bloc` / `Cubit` | every span |
| `bloc.event` | the observer hook name | every span |
| `bloc.event.type` | `transition.event.runtimeType` | `transition` spans |
| `bloc.event.value` | `event.toString()` (clipped) | when `recordEventValues: true` |
| `bloc.state.before` | `change.currentState.runtimeType` | `transition` / `change` |
| `bloc.state.after` | `change.nextState.runtimeType` | `transition` / `change` |
| `bloc.state.before.value` / `bloc.state.after.value` | `toString()` (clipped) | when `recordStateValues: true` |

## Configuration

| Constructor arg | Default | Effect |
|---|---|---|
| `tracer` | `OTel.tracerProvider().getTracer('otel_bloc')` | The tracer that emits the spans. |
| `recordLifecycle` | `true` | Emit `onCreate` / `onClose` spans. |
| `recordTransitions` | `true` | Emit `onTransition` (Bloc) / `onChange` (Cubit) spans. |
| `recordEventValues` | `false` | Capture `event.toString()` on transition spans. Off because events often carry user data. |
| `recordStateValues` | `false` | Capture state `toString()` (before + after). Off by default for the same reason. |
| `valueAttributeMaxLength` | `256` | Cap on any `toString()`-derived attribute. |

## Caveats

- The observer calls `OTel.tracerProvider().getTracer(...)` in its
  constructor — `OTel.initialize()` must run first.
- Bloc routes errors thrown inside event handlers through *both*
  `onError` (which produces an Error-status span) and the
  surrounding `Zone.handleUncaughtError`. If your app crashes when
  an event handler throws, that's bloc's existing behavior, not the
  observer — wrap the call site in `runZonedGuarded` if you need to
  swallow it.
- `Bloc.observer` is a global. Replacing it mid-app drops the
  previous one. Use `MultiBlocObserver` to compose.

## License

Apache 2.0 — see `LICENSE`.
