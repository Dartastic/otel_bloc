# otel_bloc example app

A standalone runnable demo of `otel_bloc`
exporting telemetry to a local LGTM stack (Grafana + Loki + Tempo +
Mimir). Uses `DOTel.initialize` from the Pro SDK to demonstrate the
one-character switch — package source still works with the OSS SDK.

## Run

```sh
# 1. Start the LGTM stack (from the dartastic-pro repo root)
docker compose -f tool/lgtm/docker-compose.yml up -d

# 2. Run the app
cd dart/otel_bloc/example_app
dart pub get
dart run bin/main.dart
```

## What it does

Three scenarios producing one `run-scenarios` trace with 16 spans:

| Scenario | Spans produced |
|---|---|
| `bloc-happy-path` | `bloc.created:_CounterBloc` + 2× `bloc.transition:_CounterBloc` + `bloc.closed:_CounterBloc` |
| `cubit-happy-path` | `bloc.created:_CounterCubit` + 3× `bloc.change:_CounterCubit` + `bloc.closed:_CounterCubit` |
| `bloc-error` | `bloc.created:_CounterBloc` + `bloc.error:_CounterBloc` (status=Error, exception event) + `bloc.closed:_CounterBloc` |

The Bloc transitions show `onTransition` spans (which carry the
triggering event) and *no* duplicate `onChange` spans — the
observer correctly suppresses `onChange` for Blocs since
`onTransition` strictly subsumes it.

The Cubit shows `onChange` spans and *no* `onTransition` spans —
Cubits don't have events.

## Where to look

Grafana → Explore → Tempo datasource:

- Service name: `bloc-otel-example-app`
- Open the `run-scenarios` trace.
- Click any `bloc.transition:_CounterBloc` span — the attributes
  show `bloc.event.type=_Increment`, `bloc.state.before=int`,
  `bloc.state.after=int`. The example also sets
  `recordEventValues: true` and `recordStateValues: true`, so you
  also see `bloc.event.value` and `bloc.state.before.value` /
  `bloc.state.after.value`.
- Click the `bloc.error:_CounterBloc` span — status is Error and
  it has an `exception` event with the stack trace.

## Env

| Variable | Default | Purpose |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | OTLP HTTP endpoint (the SDK's default protocol). For gRPC, also set `OTEL_EXPORTER_OTLP_PROTOCOL=grpc` and point at port 4317. |
