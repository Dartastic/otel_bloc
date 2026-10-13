<!-- dartastic-header:start -->
# OpenTelemetry instrumentation for `bloc`

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![OpenTelemetry Specification](https://img.shields.io/badge/OpenTelemetry-Specification-blueviolet)](https://opentelemetry.io/docs/specs/otel/)

`otel_bloc` is an [OpenTelemetry](https://opentelemetry.io/) instrumentation for `bloc` that
easily adds standard observability to applications that use `bloc`.  This package depends on 
[dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api).

This package can be used with any OTel backend because it's compliant with the OpenTelemetry Specification.

This package supports Android, iOS, Linux, macOS, Web and Windows, for versions of `bloc` that support those platforms. It is WASM-ready.

This package is professionally maintained and supported with 💙 by Michael Bushe, Dart and Flutter Maintainer at OpenTelemetry
and the creator of [dartastic_opentelemetry](https://pub.dev/packages/dartastic_opentelemetry)
and [dartastic_opentelemetry_api](https://pub.dev/packages/dartastic_opentelemetry_api).

This package is professionally maintained for the Dart and Flutter community and professionally supported by 
[Dartastic.io](https://dartastic.io).

---
## Dartastic.io: AI Code Healing and Real User Monitoring for Flutter

**See what your users experience. Find problems with Flutter apps in production. Fix them with AI.**

[Dartastic.io](https://dartastic.io) brings AI code healing, real user monitoring, and OpenTelemetry observability together in one platform built for Dart and Flutter. (Patents pending)

![Dartastic AI answering "Why did crashes jump after the last release?" over a Flutter App Health dashboard](https://dartastic.io/img/pub-dev/HomePageCrashesQuestion.png)

### Dartastic AI — From Production Problems to Code Fixes

Dartastic AI analyzes production telemetry alongside your application source code to diagnose problems and propose fixes.

- **Investigate production issues** using crashes, errors, traces, metrics, and real user telemetry.
- **Find the offending code** by connecting observed problems with your application's source in Dartastic Pub or your source code repos.
- **Generate code patches** that address the underlying problems.
- **Create actionable issues** in your issue tracker, complete with findings and the proposed code patch.

### Dartastic RUM — See What Your Users See

Understand how people actually experience your Flutter application.

- **Replay user sessions** in the Dartastic Observatory session player.
- **Choose your replay fidelity**, from privacy-preserving widget outlines to pixel-level reproductions of the user experience.
- **Investigate real user problems** using session replay and production observability data.

![Dartastic RUM Session Replay](https://dartastic.io/img/pub-dev/session-replay.png)

### Dartastic Observatory — Observability Built for Flutter

A complete observability backend where Flutter and Dart are first-class citizens.

- **Flutter-specific dashboards** for application performance, health, and reliability.
- **Alerts and notifications** through email, Slack, and PagerDuty.
- **Dartastic Cloud Observatory** — Start with a 30-day free trial on isolated, shared infrastructure, as low as $39/mo.
- **Dartastic Hosted Observatory** — Run the observability stack in a private managed environment, sized from Mini to Enterprise XL.
- **Dartastic Self-Hosted Observatory** — The whole platform inside your own network. Your keys, your cluster, with nothing leaving your perimeter.

### Dartastic Native OTel Runtime — Native OpenTelemetry Performance

Collect production telemetry without burdening Flutter's main isolate.

- **Native OpenTelemetry runtime** that moves telemetry processing off the main isolate.
- **Native crash reporting** for problems that Dart can't catch.
- **Widget performance diagnostics** to identify janky widgets.
- **On-device PII filtering** before sensitive data leaves your application.
- **Source-level error diagnostics** powered by the Dartastic Symbolizer API.
- **Platform-native metrics** for iOS, Android, and Linux, including iOS MetricKit and Android Vitals.
- **OpenTelemetry compatibility** — Send telemetry to Dartastic Observatory or any OpenTelemetry platform.

### Dartastic Labs — OpenTelemetry Integrations

Instrument more of your application without writing everything yourself.

- **650+ open-source integrations** for Dart and Flutter libraries and services, including Dio, Shelf, Logger, Anthropic, AWS, Azure, and Stripe. Look for otel_* on pub.dev.

### More Dartastic Tools

**[Dartastic Pub](https://dartastic.io/pub)**

A private Dart package registry for sharing packages and plugins with your team, partners, and customers.

**[Dartastic Symbolizer](https://dartastic.io/symbolizer)**

Turn production errors into lines of source code through a web API, while keeping your source code artifacts private.

### Professional Support and Training

Dartastic.io offers commercial support for the open-source `dartastic_opentelemetry` and `dartastic_opentelemetry_api` packages and the complete Dartastic product suite.

- **Professional support** with available around-the-clock coverage and response times under four hours on qualifying plans.
- **OpenTelemetry training** for teams instrumenting Dart, Flutter, mobile, and web applications.

### Open Standards. No Mandatory Backend.

The Dartastic OpenTelemetry API and SDK are open source and standards-based. You can use them independently of Dartastic's commercial services and send telemetry to any compatible OpenTelemetry backend.

Dartastic's commercial products add native performance, advanced diagnostics, session replay, AI-assisted remediation, and managed observability services.

**[Explore Dartastic.io](https://dartastic.io)**

---
<!-- dartastic-header:end -->

OpenTelemetry instrumentation for [`package:bloc`](https://pub.dev/packages/bloc),
built on the [Dartastic OpenTelemetry SDK](https://pub.dev/packages/dartastic_opentelemetry).

Install one `BlocObserver` and every bloc / cubit lifecycle event
emits a short span — created, transition, change, error, closed —
turning your trace view into a state-machine timeline.

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
package emits a span per observer hook, so your trace backend's
waterfall view shows you the exact sequence that led to a bad
state, ordered and timestamped, with the triggering event captured.

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

## Context propagation

Bloc runs an event handler from a stream subscription created when
the bloc was *constructed*, not from the zone that called `add`.
OpenTelemetry context lives in zones, so by default a span made
current around `bloc.add(...)` (a gesture span, say) is **not** the
parent of anything the handler does: its HTTP calls, its database
calls, or the `bloc.transition` span.

`otelContextTransformer` fixes that. The observer's `onEvent` hook
runs synchronously inside `add`, in the caller's zone, and captures
the current context; the transformer runs the handler inside it. The
handler, everything it awaits, and every span it starts then nest
under the caller's span.

Install both once, **before any bloc is constructed** (a bloc reads
`Bloc.transformer` in its constructor):

```dart
Bloc.observer = OTelBlocObserver();
Bloc.transformer = otelContextTransformer(Bloc.transformer);
```

Handlers that pass their own transformer wrap it the same way:

```dart
on<Refresh>(_onRefresh, transformer: otelContextTransformer(droppable()));
```

Notes:

- Cubits need nothing: their methods are plain calls that already run
  in the caller's zone.
- Each event's context is claimed as it leaves the bloc's event
  stream, before your transformer drops, debounces or queues it, so a
  dropped event never hands its context to a later one.
- Events that are `null`, numbers, strings, booleans or records can't
  carry a captured context and run without propagation. Use a class
  or enum for events you want traced end to end.
- The same `const` event instance added several times shares one
  first-in, first-out queue (capped at 64). With `restartable` or a
  debounce, the event that survives can take an earlier `add`'s
  context.
- `OTelBlocObserver(propagateContext: false)` turns the capture off.

## Span shape

| Bloc kind | Hook           | Span name                | Status                    |
|-----------|----------------|--------------------------|---------------------------|
| Any       | `onCreate`     | `bloc.created:<name>`    | unset                     |
| `Bloc`    | `onTransition` | `bloc.transition:<name>` | unset                     |
| `Cubit`   | `onChange`     | `bloc.change:<name>`     | unset                     |
| Any       | `onError`      | `bloc.error:<name>`      | Error + `recordException` |
| Any       | `onClose`      | `bloc.closed:<name>`     | unset                     |

`onChange` is suppressed for `Bloc`s because `onTransition` fires
right after it with strictly more info (the triggering event).
Cubits don't have events, so only `onChange` fires for them.

| Attribute                                            | Source                            | When set                       |
|------------------------------------------------------|-----------------------------------|--------------------------------|
| `bloc.name`                                          | `bloc.runtimeType`                | every span                     |
| `bloc.kind`                                          | `Bloc` / `Cubit`                  | every span                     |
| `bloc.event`                                         | the observer hook name            | every span                     |
| `bloc.event.type`                                    | `transition.event.runtimeType`    | `transition` spans             |
| `bloc.event.value`                                   | `event.toString()` (clipped)      | when `recordEventValues: true` |
| `bloc.state.before`                                  | `change.currentState.runtimeType` | `transition` / `change`        |
| `bloc.state.after`                                   | `change.nextState.runtimeType`    | `transition` / `change`        |
| `bloc.state.before.value` / `bloc.state.after.value` | `toString()` (clipped)            | when `recordStateValues: true` |

## Configuration

| Constructor arg           | Default                                        | Effect                                                                                                                  |
|---------------------------|------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| `tracer`                  | `OTel.tracerProvider().getTracer('otel_bloc')` | The tracer that emits the spans.                                                                                        |
| `recordLifecycle`         | `true`                                         | Emit `onCreate` / `onClose` spans.                                                                                      |
| `recordTransitions`       | `true`                                         | Emit `onTransition` (Bloc) / `onChange` (Cubit) spans.                                                                  |
| `recordEventValues`       | `false`                                        | Capture `event.toString()` on transition spans. Off because events often carry user data.                               |
| `recordStateValues`       | `false`                                        | Capture state `toString()` (before + after). Off by default for the same reason.                                        |
| `valueAttributeMaxLength` | `256`                                          | Cap on any `toString()`-derived attribute.                                                                              |
| `propagateContext`        | `true`                                         | Capture the caller's context on `Bloc.add` for `otelContextTransformer`. No effect unless the transformer is installed. |

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
