# Contributing to VoxWrite

Thank you for helping improve VoxWrite. Contributions in Chinese or English are welcome.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Contributions intentionally submitted to this project are licensed under the [Apache License 2.0](LICENSE).

## Before you start

- Search existing issues before opening a new one.
- Use an issue to discuss substantial features or behavior changes before implementation.
- Never include API keys, credentials, private recordings, or sensitive text in issues, logs, tests, or commits.
- Report security vulnerabilities privately according to [SECURITY.md](SECURITY.md).

## Development setup

Install a stable Flutter SDK compatible with the constraints in `pubspec.yaml` and `pubspec.lock`, then run:

```bash
flutter pub get
flutter analyze
flutter test
```

Platform-specific requirements and run commands are documented in [README.md](README.md) and [README.en.md](README.en.md).

## Making a change

1. Fork the repository and create a focused branch.
2. Keep changes small and avoid unrelated refactors.
3. Add or update tests for behavior changes.
4. Format Dart code with `dart format lib test`.
5. Run `flutter analyze` and `flutter test`.
6. Update documentation when configuration or user-visible behavior changes.
7. Open a pull request and explain the motivation, approach, and validation performed.

Conventional-style commit messages such as `feat:`, `fix:`, `docs:`, and `test:` are encouraged.

## Pull requests

A pull request should:

- Describe what changed and why.
- Link related issues where applicable.
- Include screenshots or recordings for UI changes, with private information removed.
- Identify the platforms that were tested.
- Pass continuous integration checks.

Maintainers may request changes to keep the project secure, maintainable, and consistent across platforms.
