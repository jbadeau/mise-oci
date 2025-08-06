# Example

## Generate Mise stub

```shell
mise generate tool-stub azul-zulu-17.60.17.toml \
  --version 17.60.17\
  --platform-url linux-x64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-linux_x64.tar.gz \
  --platform-url linux-arm64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-linux_aarch64.tar.gz \
  --platform-url darwin-x64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-macosx_x64.tar.gz \
  --platform-url darwin-arm64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-macosx_aarch64.tar.gz \
  --platform-url windows-x64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-win_x64.zip \
  --platform-url windows-arm64:https://cdn.azul.com/zulu/bin/zulu17.60.17-ca-jdk17.0.16-win_aarch64.zip
```

## Publish Mise stub as OCI artifact to local docker registry

```shell
./publish.sh azul-zulu-17.60.17.toml localhost:5000
```

## Publish Mise stub as OCI artifact to dockerhub

```shell
./publish.sh azul-zulu-17.60.17.toml docker.io/jbadeau
```

## Inspect OCI artifact manifest

```shell
oras manifest fetch docker.io/jbadeau/azul-zulu:17.60.17 | jq
```