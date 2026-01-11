# Contributing to Vigil

Thank you for your interest in contributing to Vigil! This document provides guidelines and information for contributors.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

## How to Contribute

### Reporting Issues

Before creating an issue, please:

1. Search existing issues to avoid duplicates
2. Use the issue templates when available
3. Provide detailed reproduction steps for bugs
4. Include system information (OS version, Xcode version, device type)

### Security Vulnerabilities

**Do not report security vulnerabilities through public issues.**

Instead, please email security@vigil-project.dev with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact assessment
- Any suggested fixes (optional)

We will respond within 48 hours and work with you on responsible disclosure.

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Follow the coding style** of the existing codebase
3. **Add tests** for new functionality
4. **Update documentation** as needed
5. **Ensure all tests pass** before submitting
6. **Write clear commit messages** following conventional commits

#### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Example:
```
feat(HashEngine): add support for multi-architecture binaries

- Handle universal binaries with multiple slices
- Extract and hash the active architecture slice
- Add unit tests for arm64 and x86_64 scenarios

Closes #42
```

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/nkhmelni/Vigil.git
   cd Vigil
   ```

2. Open in Xcode:
   ```bash
   open Package.swift
   ```

3. Build and run tests:
   ```bash
   swift build
   swift test
   ```

### Testing Requirements

- All new features must include unit tests
- Integration tests required for IPC functionality
- Test on both iOS and macOS when applicable
- Physical device testing required for Secure Enclave features

### Documentation

- Update API documentation for public interface changes
- Add inline documentation for complex logic
- Update relevant markdown files in `Documentation/`

## Project Structure

```
Vigil/
├── Sources/
│   ├── Vigil/              # Main framework
│   └── VigilValidator/     # Validator components
├── Tests/
│   ├── VigilTests/
│   └── IntegrationTests/
├── Documentation/          # Markdown documentation
├── Examples/               # Sample applications
└── Tools/                  # Build tools and scripts
```

## Coding Guidelines

### Objective-C

- Use modern Objective-C syntax (`@property`, literals, etc.)
- Prefix public classes with `Vigil`
- Use nullability annotations (`nullable`, `nonnull`)
- Document public APIs with HeaderDoc comments

### Swift

- Follow Swift API Design Guidelines
- Use `final` for classes not designed for inheritance
- Prefer value types where appropriate
- Use `@MainActor` for UI-related code

### Security Considerations

When contributing security-sensitive code:

- Never log sensitive data (keys, hashes, signatures)
- Use constant-time comparison for cryptographic data
- Clear sensitive data from memory when done
- Consider timing attacks in validation logic

## Review Process

1. All PRs require at least one maintainer approval
2. CI must pass (build, tests, linting)
3. Security-sensitive changes require additional review
4. Large changes may require design discussion first

## Release Process

Releases follow semantic versioning:
- **MAJOR**: Breaking API changes
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes (backwards compatible)

## Getting Help

- Open a GitHub Discussion for questions
- Join our Discord server (link in README)
- Check existing documentation and issues first

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
