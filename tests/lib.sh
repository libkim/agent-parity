# Shared helpers for the test suite. Tests run on every supported desktop
# platform, so nothing here may assume a particular OS or architecture.

# Sets goos/goarch/ext and the platform asset names used across tests.
tests_platform() {
  ext=""
  case "$(uname -s)" in
    Linux) goos=linux ;;
    Darwin) goos=darwin ;;
    MINGW* | MSYS* | CYGWIN*) goos=windows; ext=".exe" ;;
    *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) goarch=amd64 ;;
    aarch64 | arm64) goarch=arm64 ;;
    *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
  esac
  editor_asset="agent-parity-config-${goos}-${goarch}${ext}"
  server_asset="memory-mcp-${goos}-${goarch}${ext}"
}

# sha256 checksum verification; macOS ships shasum instead of sha256sum.
tests_verify_checksums() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$1"
  else
    shasum -a 256 -c "$1"
  fi
}
