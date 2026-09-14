#!/usr/bin/env bash
# Sign the completed bundle with a persistent identity, then verify it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/Sumbee.app}"
IDENTITY="${SUMBEE_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" && -f "$ROOT/.signing-identity" ]]; then
    IFS= read -r IDENTITY < "$ROOT/.signing-identity"
fi
if [[ -z "$IDENTITY" ]]; then
    echo "Run bash scripts/setup-signing.sh to select your Apple Development certificate." >&2
    exit 1
fi

if [[ "$IDENTITY" == "-" ]]; then
    echo "Ad-hoc signing cannot preserve Sumbee's code-signing identity across builds." >&2
    exit 1
fi

IDENTITIES="$(security find-identity -v -p codesigning)"
if [[ "$IDENTITIES" != *"\"$IDENTITY\""* && "$IDENTITIES" != *" $IDENTITY \""* ]]; then
    echo "No valid signing identity: $IDENTITY" >&2
    echo "Check its private key and Apple WWDR intermediate, then run bash scripts/setup-signing.sh." >&2
    echo "SUMBEE_SIGNING_IDENTITY can also select a valid certificate name or fingerprint." >&2
    exit 1
fi
if [[ "$APP" == "--check" ]]; then exit 0; fi

# Resource-only SwiftPM bundles are sealed as app resources. The default
# designated requirement pins the certificate and identifier, not the binary hash.
codesign --force --sign "$IDENTITY" --timestamp=none \
    --identifier com.sumbee.app "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "▸ Signed with $IDENTITY"
