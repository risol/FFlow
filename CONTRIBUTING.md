# Contributing to FFlow

## Development setup

Install Flutter 3.27 or later and use the repository root as the package
directory. The example is a separate consumer app under `example/`.

```powershell
flutter pub get
flutter analyze
flutter test
cd example
flutter pub get
flutter run -d windows
```

## Before sending a change

- Format Dart code with `dart format lib test benchmark example/lib`.
- Add unit or widget coverage for behavior changes.
- Update `CHANGELOG.md` under `Unreleased` for user-visible changes.
- Update the relevant architecture or interaction documentation when a public
  API or coordinate rule changes.
- Keep the root package free of runtime third-party dependencies. Put optional
  layout, routing, and collaboration integrations in adapter packages.

## Benchmarking

Run the deterministic graph benchmark with:

```powershell
flutter test benchmark/large_graph_benchmark_test.dart
```

The harness reports graph index construction, cached edge geometry, broad-phase
index construction, and query candidate counts for fixed graph sizes. Compare
results on the same machine and Flutter/Dart version.

## Pull request checklist

- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] Public API has Dart documentation and an example or test.
- [ ] Breaking 0.x API changes have a migration note.
- [ ] `CHANGELOG.md` is updated.
