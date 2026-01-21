# Contributing to Clean Kanban

Thank you for your interest in contributing to Clean Kanban! This document provides guidelines and steps for contributing.

## Code of Conduct

By participating in this project, you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the issue list as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title**
* **Describe the exact steps to reproduce the problem**
* **Provide specific examples to demonstrate the steps**
* **Describe the behavior you observed after following the steps**
* **Explain which behavior you expected to see instead and why**
* **Include screenshots or animated GIFs if possible**
* **Include your environment details** (Flutter version, Dart version, OS, etc.)

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

* **Use a clear and descriptive title**
* **Provide a step-by-step description of the suggested enhancement**
* **Provide specific examples to demonstrate the steps**
* **Describe the current behavior and explain the behavior you expected to see**
* **Explain why this enhancement would be useful**

### Pull Requests

* Fork the repo and create your branch from `main`
* If you've added code that should be tested, add tests
* If you've changed APIs, update the documentation
* Ensure the test suite passes
* Make sure your code lints
* Follow the existing code style
* Write a good commit message

## Development Setup

1. Fork and clone the repository
2. Install dependencies:
```bash
flutter pub get
```

3. Run tests:
```bash
flutter test
```

## Style Guide

### Dart Style

* Follow the [Effective Dart: Style Guide](https://dart.dev/guides/language/effective-dart/style)
* Use `dart format` to format your code
* Run `flutter analyze` to check for issues

### Git Commit Messages

* Use the present tense ("Add feature" not "Added feature")
* Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
* Limit the first line to 72 characters or less
* Reference issues and pull requests liberally after the first line

Example:
```
feat: Add column limit validation

- Add validation for maximum tasks per column
- Update documentation for column limits
- Add tests for validation logic

Fixes #123
```

## Testing

* Write test cases for new features
* Ensure all tests pass before submitting PR
* Follow the existing test patterns in the codebase
* Include both unit and widget tests where appropriate

## Documentation

* Update README.md with details of changes to the interface
* Update API documentation for any modified code
* Add examples for new features
* Keep the documentation clear and concise

## Review Process

1. Create a Pull Request with a clear title and description
2. Wait for review from maintainers
3. Make changes if requested
4. Once approved, your PR will be merged

## Release Process

1. Update version in `pubspec.yaml`
2. Update CHANGELOG.md
3. Create a new GitHub release
4. Tag the release following semver (e.g., v1.0.0)

## Questions?

Feel free to open an issue with your question or reach out to the maintainers.

## License

By contributing, you agree that your contributions will be licensed under the GNU General Public License v3.0.