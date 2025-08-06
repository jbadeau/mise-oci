#!/usr/bin/env bash
set -euo pipefail

main() {
  check_dependencies
  parse_args "$@"

  absolute_mise_stub_file=$(get_absolute_path "$mise_stub_file_arg")
  parse_image_name_and_tag "$absolute_mise_stub_file"
  image_name="$registry/$namespace/$image_name_base"

  parse_global_annotations "$absolute_mise_stub_file"

  work_dir=$(mktemp -d)
  trap "rm -rf '$work_dir'" EXIT
  cd "$work_dir"

  process_platforms "$absolute_mise_stub_file" "$image_name" "$tag"
  echo "✅ Published OCI artifact: $image_name:$tag"
}

check_dependencies() {
  for cmd in tomlq oras curl b3sum; do
    if ! command -v "$cmd" >/dev/null; then
      echo "❌ '$cmd' is required but not installed."
      echo "   Install tomlq with: pip install yq"
      exit 1
    fi
  done
}

parse_args() {
  if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <mise_stub_file> <registry/namespace>" >&2
    echo "Example: $0 tool.toml docker.io/username" >&2
    exit 1
  fi

  mise_stub_file_arg="$1"
  registry_namespace="$2"
  
  # Split registry/namespace - require both parts
  if [[ "$registry_namespace" == *"/"* ]]; then
    registry="${registry_namespace%%/*}"
    namespace="${registry_namespace#*/}"
  else
    echo "❌ Registry/namespace must be in format 'registry/namespace'" >&2
    echo "Example: docker.io/username" >&2
    exit 1
  fi

  if [[ ! -f "$mise_stub_file_arg" ]]; then
    echo "❌ File not found: $mise_stub_file_arg" >&2
    exit 1
  fi
}

get_absolute_path() {
  local file_path="$1"
  if command -v realpath &>/dev/null; then
    realpath "$file_path"
  else
    cd "$(dirname "$file_path")" && echo "$(pwd)/$(basename "$file_path")"
  fi
}

parse_image_name_and_tag() {
  image_name_base=$(tomlq -r '.tool' "$1")
  tag=$(tomlq -r '.version // "latest"' "$1")
  if [[ -z "$image_name_base" ]]; then
    echo "❌ Missing 'tool' in mise stub manifest"
    exit 1
  fi
}

parse_global_annotations() {
  local file="$1"
  title=$(tomlq -r '.tool // empty' "$file")
  description="Mise tool: $(tomlq -r '.tool // empty' "$file")"
  version=$(tomlq -r '.version // "latest"' "$file")
  authors=""
  license=""
  source=""
  documentation=""
  url=""
  vendor="mise"
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
}

normalize_platform() {
  case "$1" in 
    macos|darwin) os="darwin" ;; 
    *) os="$1" ;; 
  esac
  case "$2" in 
    x86_64|amd64) arch="amd64" ;; 
    aarch64) arch="arm64" ;; 
    x64) arch="amd64" ;;
    *) arch="$2" ;; 
  esac
}

process_platforms() {
  local mise_stub_file="$1" image_name="$2" tag="$3"
  local platform_files=()
  local platform_annotations=()

  # Get platform keys from TOML
  while IFS= read -r platform_key; do
    platform_key=$(echo "$platform_key" | sed 's/"//g')  # Remove quotes
    
    # Extract platform data from TOML
    local url expected_checksum format bin_path
    url=$(tomlq -r ".platforms.\"$platform_key\".url" "$mise_stub_file")
    expected_checksum=$(tomlq -r ".platforms.\"$platform_key\".checksum // empty" "$mise_stub_file")
    bin_path=$(tomlq -r ".platforms.\"$platform_key\".bin // \"bin/java\"" "$mise_stub_file")
    
    # Skip if no URL
    if [[ "$url" == "null" || -z "$url" ]]; then
      continue
    fi
    
    # Handle blake3: prefix in checksum
    if [[ "$expected_checksum" =~ ^blake3: ]]; then
      expected_checksum="${expected_checksum#blake3:}"
    fi

    normalize_platform "$(echo "$platform_key" | cut -d'-' -f1)" "$(echo "$platform_key" | cut -d'-' -f2)"

    filename=$(basename "$url")
    
    echo "📦 Downloading $filename for $os/$arch"
    curl -fsSL -o "$filename" "$url"

    # Only verify checksum if provided
    if [[ -n "$expected_checksum" && "$expected_checksum" != "empty" ]]; then
      actual_digest=$(b3sum "$filename" | awk '{print $1}')
      if [[ "$actual_digest" != "$expected_checksum" ]]; then
        echo "❌ BLAKE3 digest mismatch for $filename"
        echo "Expected: $expected_checksum"
        echo "Actual:   $actual_digest"
        exit 1
      fi
      echo "✅ Verified BLAKE3 digest"
    else
      echo "⚠️  No checksum provided, skipping verification"
    fi

    # Detect format from filename and use MTA media types
    case "$filename" in
      *.tar.gz)   media_type="application/vnd.mise.tool.layer.v1.tar+gzip" ;;
      *.tar.xz)   media_type="application/vnd.mise.tool.layer.v1.tar+xz" ;;
      *.tar.zst)  media_type="application/vnd.mise.tool.layer.v1.tar+zstd" ;;
      *.zip)      media_type="application/vnd.mise.tool.layer.v1.zip" ;;
      *.vsix)     media_type="application/vnd.mise.tool.layer.v1.vsix" ;;
      *)          media_type="application/vnd.mise.tool.layer.v1.bin" ;;
    esac

    # Add MTA-compliant annotations to the file
    platform_files+=("$filename:$media_type")
    platform_annotations+=(
      "--annotation" "$filename:org.mise.tool.filename=$filename"
      "--annotation" "$filename:org.mise.tool.executable=$bin_path"
      "--annotation" "$filename:org.mise.tool.checksum.blake3=blake3:$expected_checksum"
      "--annotation" "$filename:org.mise.download.url=$url"
      "--annotation" "$filename:org.mise.download.size=$(stat -c%s "$filename" 2>/dev/null || stat -f%z "$filename" 2>/dev/null || echo '0')"
    )

  done < <(tomlq -r '.platforms | keys[]' "$mise_stub_file")

  # Create single OCI artifact with all platform files as layers
  local final_ref="${image_name}:${tag}"
  echo "📦 Creating MTA artifact: $final_ref"
  
  # Create MTA-compliant config object
  create_mta_config "$mise_stub_file" > config.json
  config_media_type="application/vnd.mise.tool.v1+json"

  oras push "$final_ref" \
    --config "config.json:$config_media_type" \
    "${platform_files[@]}" \
    "${platform_annotations[@]}" \
    --annotation "org.mise.tool.name=$image_name_base" \
    --annotation "org.mise.tool.version=$version" \
    --annotation "org.mise.tool.description=$description" \
    --annotation "org.mise.tool.homepage=$url" \
    --annotation "org.mise.tool.documentation=$documentation" \
    --annotation "org.mise.tool.source=$source" \
    --annotation "org.mise.tool.license=$license" \
    --annotation "org.mise.tool.vendor=$vendor" \
    --annotation "org.opencontainers.image.created=$created" \
    --annotation "org.opencontainers.image.authors=$authors"
}

create_mta_config() {
  local mise_stub_file="$1"
  
  # Extract platform data for config
  local platforms_json="{}"
  while IFS= read -r platform_key; do
    platform_key=$(echo "$platform_key" | sed 's/"//g')
    
    local url expected_checksum bin_path size_value
    url=$(tomlq -r ".platforms.\"$platform_key\".url" "$mise_stub_file")
    expected_checksum=$(tomlq -r ".platforms.\"$platform_key\".checksum // empty" "$mise_stub_file")
    bin_path=$(tomlq -r ".platforms.\"$platform_key\".bin // \"bin/java\"" "$mise_stub_file")
    size_value=$(tomlq -r ".platforms.\"$platform_key\".size // 0" "$mise_stub_file")
    
    if [[ "$url" != "null" && -n "$url" ]]; then
      # Handle blake3: prefix
      if [[ "$expected_checksum" =~ ^blake3: ]]; then
        expected_checksum="${expected_checksum#blake3:}"
      fi
      
      platforms_json=$(echo "$platforms_json" | jq \
        --arg key "$platform_key" \
        --arg url "$url" \
        --arg checksum "blake3:$expected_checksum" \
        --arg bin "$bin_path" \
        --arg size "$size_value" \
        '.[$key] = {url: $url, checksum: $checksum, bin: $bin, size: ($size | tonumber)}')
    fi
  done < <(tomlq -r '.platforms | keys[]' "$mise_stub_file")

  # Generate MTA config JSON
  jq -n \
    --arg tool "$image_name_base" \
    --arg version "$version" \
    --arg bin "bin/java" \
    --arg description "$description" \
    --arg homepage "$url" \
    --arg license "$license" \
    --arg category "runtime" \
    --argjson platforms "$platforms_json" \
    --arg created "$created" \
    '{
      mtaSpecVersion: "1.0",
      tool: $tool,
      version: $version,
      bin: $bin,
      description: $description,
      homepage: $homepage,
      license: $license,
      category: $category,
      platforms: $platforms,
      env: {
        JAVA_HOME: "{{ install_path }}",
        PATH: "{{ install_path }}/bin:{{ PATH }}"
      },
      post_install: [
        "chmod +x {{ install_path }}/bin/*"
      ],
      validation: {
        command: ($tool | if test("java|jdk|zulu") then "java -version" else ($tool + " --version") end),
        expected_output_regex: ".*"
      },
      metadata: {
        backends: ["http", "asdf"],
        source: "",
        build_info: {
          build_date: $created,
          build_system: "mise-mta",
          build_version: "1.0.0"
        }
      }
    }'
}

main "$@"
