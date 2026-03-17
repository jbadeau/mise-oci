# mise-oci

A [Mise](https://github.com/jdx/mise) backend plugin for installing tools from OCI registries using the [MTA specification](https://github.com/jbadeau/mise-tool-artifact-specification).

> **Warning**
> This plugin is under active development and is considered unstable. APIs, configuration options, and behavior may change without notice.

## How It Works

The plugin pulls multi-platform tool artifacts from any OCI-compatible registry. Each artifact is an OCI Image Index containing per-platform manifests with a config blob (install behavior) and a payload layer (the original upstream binary/archive).

```
oci:java@17.64.17
  → fetch Image Index from registry
  → resolve platform manifest (darwin/arm64)
  → read config (bin, env, stripComponents)
  → download payload layer
  → extract and install
```

## Installation

Add to your `mise.toml`:

```toml
[plugins]
oci = "https://github.com/jbadeau/mise-oci.git"

[settings]
experimental = true
```

Requires [oras](https://oras.land/) on your PATH.

## Configuration

Configure the registry via environment variables or `[env]` in `mise.toml`:

```toml
[env]
MISE_OCI_REGISTRY = "localhost:5000"
MISE_OCI_REPOSITORY = "tools"
MISE_OCI_INSECURE = "true"        # for HTTP registries
```

| Variable | Required | Description |
|----------|----------|-------------|
| `MISE_OCI_REGISTRY` | yes | Registry host (e.g. `docker.io`, `localhost:5000`) |
| `MISE_OCI_REPOSITORY` | yes | Repository path prefix |
| `MISE_OCI_INSECURE` | no | Set to `true` for HTTP registries |

For private registries, authenticate with `oras login` before installing.

## Usage

```toml
[tools]
"oci:java" = "17.64.17"
```

```sh
mise install
mise exec -- java -version
```

Or directly from the CLI:

```sh
mise ls-remote oci:java
mise install oci:java@17.64.17
mise exec oci:java@17.64.17 -- java -version
```

## MTA Config

The plugin reads the MTA config blob from each platform manifest to determine install behavior:

| Field | Description |
|-------|-------------|
| `stripComponents` | Number of leading directory components to strip during extraction (default: `0`) |
| `bin` | Paths to executables or directories (trailing `/` = all executables in directory) |
| `env` | Environment variables with template substitution (`{{ install_path }}`, `{{ path_list_sep }}`) |

## Supported Payload Formats

The plugin auto-detects the payload format from the layer media type or file signature:

| Format | Media Type |
|--------|------------|
| tar.gz | `application/vnd.oci.image.layer.v1.tar+gzip` |
| tar.xz | `application/vnd.oci.image.layer.v1.tar+zstd` |
| zip | `application/zip` |
| standalone binary | `application/octet-stream` |

## Examples

See [examples/nexus](examples/nexus) for a complete walkthrough using a local Nexus OCI registry.

## Troubleshooting

| Error | Solution |
|-------|----------|
| Missing required environment variables | Set `MISE_OCI_REGISTRY` and `MISE_OCI_REPOSITORY` |
| No platform manifest found | Tool missing binary for your OS/arch |
| custom backends is experimental | Add `experimental = true` to `[settings]` |
| Authentication required | Run `oras login <registry>` |

## Development

```sh
mise plugin link oci $PWD --force
MISE_OCI_REGISTRY=localhost:5000 MISE_OCI_REPOSITORY=tools MISE_OCI_INSECURE=true MISE_EXPERIMENTAL=1 mise install oci:java@17.64.17
```
