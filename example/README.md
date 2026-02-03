# Example

## Step 1: Generate a tool stub

### Option A: From HTTP URLs

```shell
mise generate tool-stub azul-zulu-17.60.17.toml \
  --version 17.60.17 \
  --platform-url linux-x64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-linux_x64.tar.gz \
  --platform-url linux-arm64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-linux_aarch64.tar.gz \
  --platform-url darwin-x64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-macosx_x64.tar.gz \
  --platform-url darwin-arm64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-macosx_aarch64.tar.gz \
  --platform-url windows-x64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-win_x64.zip \
  --platform-url windows-arm64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-win_aarch64.zip
```

### Option B: From local binaries

```shell
./generate-local-stub.sh my-tool 1.0.0 \
  --platform-file linux-x64:./build/my-tool-linux-x64.tar.gz \
  --platform-file linux-arm64:./build/my-tool-linux-arm64.tar.gz \
  --platform-file darwin-x64:./build/my-tool-darwin-x64.tar.gz \
  --platform-file darwin-arm64:./build/my-tool-darwin-arm64.tar.gz \
  --bin bin/my-tool \
  --output my-tool-1.0.0.toml
```

Options:
- `--platform-file <platform:path>` - Platform and local file path (required, can be repeated)
- `--bin <path>` - Default binary path within archive
- `--platform-bin <platform:path>` - Platform-specific binary path
- `--output <file>` - Output file (default: stdout)

## Step 2: Publish tool stub as OCI artifact

```shell
./publish.sh azul-zulu-17.60.17.toml docker.io/jbadeau
```

Both HTTP URLs and local file (`file://`) URLs are supported.

## Step 3: Inspect OCI artifact manifest

```shell
oras manifest fetch docker.io/jbadeau/azul-zulu:17.60.17 | jq
```
