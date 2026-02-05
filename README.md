# mise-oci

A [Mise](https://github.com/jdx/mise) backend plugin for installing tools from OCI registries.

> **⚠️ Under heavy development** - expect breaking changes until v1.0.

## Installation

Requires [Mise](https://github.com/jdx/mise) v2025.1.0+ and [oras](https://oras.land/).

```sh
mise plugin install oci https://github.com/jbadeau/mise-oci.git
```

## Configuration

Set your registry and repository:

```sh
export MISE_OCI_REGISTRY="docker.io"
export MISE_OCI_REPOSITORY="jbadeau"
```

For private registries, also set credentials or use `oras login`:

```sh
export MISE_OCI_USERNAME="user"
export MISE_OCI_PASSWORD="pass"
```

## Usage

```sh
# Install and run
mise install oci:azul-zulu@17.60.17
mise exec oci:azul-zulu@17.60.17 -- java --version

# List versions
mise ls-remote oci:azul-zulu
```

In `.mise.toml`:

```toml
[tools]
"oci:azul-zulu" = "17.60.17"
```

## Publishing Tools

See [example/README.md](example/README.md) for publishing tools and [example/SPECIFICATION.md](example/SPECIFICATION.md) for the MTA specification.

## Troubleshooting

| Error | Solution |
|-------|----------|
| Tool not found | Verify OCI reference exists in registry |
| No layer found for platform | Tool missing binary for your OS/arch |
| Authentication required | Run `oras login` |
| Extraction failed | Check archive format (tar.gz, tar.xz, zip supported) |

## Development

```sh
mise plugin link oci $PWD --force
mise install oci:azul-zulu@17.60.17
```