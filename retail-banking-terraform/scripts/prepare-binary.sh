#!/usr/bin/env bash
set -euo pipefail

# Run from any directory. This script downloads Linux AMD64 on both macOS/Linux.
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="v0.26.2"
archive="fake_service_linux_amd64.zip"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$project_dir/assets"

curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 \
  "https://github.com/nicholasjackson/fake-service/releases/download/$version/$archive" \
  -o "$work_dir/$archive"
unzip -q "$work_dir/$archive" -d "$work_dir/extracted"
binary="$work_dir/extracted/fake-service"
test -f "$binary"

file_type="$(file "$binary")"
case "$file_type" in
  *"ELF 64-bit"*"x86-64"*) ;;
  *) echo "Expected a Linux x86-64 executable; got: $file_type" >&2; exit 1 ;;
esac

cp "$binary" "$project_dir/assets/fake-service"
chmod 0755 "$project_dir/assets/fake-service"
file "$project_dir/assets/fake-service"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$project_dir/assets/fake-service"
else
  shasum -a 256 "$project_dir/assets/fake-service"
fi
printf '\nBinary ready. Terraform will upload it to a new private S3 bucket.\n'
