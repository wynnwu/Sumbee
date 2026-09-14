#!/usr/bin/env bash
# Select an existing signing identity and remember its fingerprint for this checkout.
# Usage: bash scripts/setup-signing.sh [certificate-name-or-fingerprint]
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUESTED="${1:-${SUMBEE_SIGNING_IDENTITY:-}}"
IDENTITIES="$(security find-identity -v -p codesigning)"

if [[ -n "$REQUESTED" ]]; then
    MATCHES="$(printf '%s\n' "$IDENTITIES" | awk -v requested="$REQUESTED" \
        '$2 == requested || index($0, "\"" requested "\"") { print $2 }')"
else
    MATCHES="$(printf '%s\n' "$IDENTITIES" | awk '/"Apple Development: / { print $2 }')"
fi

if [[ ! "$MATCHES" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "Choose one valid signing identity by name or fingerprint:" >&2
    printf '%s\n' "$IDENTITIES" >&2
    echo "Create Apple Development in Xcode → Settings → Accounts → Manage Certificates." >&2
    echo "If it is missing here, check its private key and Apple WWDR intermediate certificate." >&2
    exit 1
fi

SIGNING_CONFIG="$(mktemp "$ROOT/.signing-identity.XXXXXX")"
trap 'rm -f "$SIGNING_CONFIG"' EXIT
printf '%s\n' "$MATCHES" > "$SIGNING_CONFIG"
mv "$SIGNING_CONFIG" "$ROOT/.signing-identity"
echo "▸ Saved signing identity for this checkout: $MATCHES"
