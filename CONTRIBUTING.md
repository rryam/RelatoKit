# Contributing

Thanks for helping improve RelatoKit.

## Development

```sh
swift build
swift test
swift run relato --help
```

The live CLI help is part of the public contract. If you change commands or flags, update the generated reference:

```sh
make generate-command-docs
make check-command-docs
```

Before opening a pull request:

```sh
make check
```

## Boundaries

RelatoKit is native Feedback Assistant automation. It should not bypass entitlements, forge Apple credentials, patch platform protections, inject into Apple processes, or implement private headless submission.

Keep research probes in `Research/`, outside the normal Swift package build.
