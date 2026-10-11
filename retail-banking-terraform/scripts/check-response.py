#!/usr/bin/env python3
"""Validate the three-service response without relying only on the outer code."""
import json
import sys

expected = ["customer-profile-svc", "account-svc", "statement-svc"]
node = json.load(sys.stdin)
for index, name in enumerate(expected):
    if node.get("name") != name or node.get("code") != 200:
        raise SystemExit(f"FAIL: expected {name} with code 200; got {node.get('name')} / {node.get('code')}")
    print(f"OK: {name} -> 200")
    calls = node.get("upstream_calls", {})
    if index < len(expected) - 1:
        if len(calls) != 1:
            raise SystemExit(f"FAIL: {name} should have exactly one upstream response")
        node = next(iter(calls.values()))
    elif calls:
        raise SystemExit("FAIL: Statement should be the final service")
