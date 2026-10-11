#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

region="$(terraform output -raw aws_region)"
target_group="$(terraform output -raw target_group_arn)"
url="$(terraform output -raw application_url)"

echo "Waiting for the Customer target to become healthy..."
aws elbv2 wait target-in-service --target-group-arn "$target_group" --region "$region"

echo "Testing $url"
response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT
curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
  "$url/" -o "$response_file"
python3 scripts/check-response.py < "$response_file"

case "$url" in
  https://*)
    # Validate canonical-host redirect, path and query preservation.
    http_url="http://${url#https://}"
    status="$(curl --silent --show-error --connect-timeout 10 --max-time 30 \
      --output /dev/null --write-out '%{http_code}' "$http_url/ui/?demo=1")"
    redirect="$(curl --silent --show-error --connect-timeout 10 --max-time 30 \
      --output /dev/null --write-out '%{redirect_url}' "$http_url/ui/?demo=1")"
    test "$status" = "301"
    test "$redirect" = "$url:443/ui/?demo=1" || test "$redirect" = "$url/ui/?demo=1"
    echo "OK: HTTP 301 redirects to HTTPS and preserves path/query"
    ;;
esac
echo "UI: $(terraform output -raw ui_url)"
