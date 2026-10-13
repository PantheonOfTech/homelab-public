#!/usr/bin/env bash
# leak-guard.sh - block private infrastructure details from entering this public repo.
#
#   bash .githooks/leak-guard.sh            scan lines added in the staged commit (pre-commit hook)
#   bash .githooks/leak-guard.sh --all      scan every tracked file (CI, or a manual audit)
#
# Enable as the repo's hook once per clone:   git config core.hooksPath .githooks
#
# Blocks: RFC 1918 and CGNAT (100.64/10, Tailscale) addresses, MAC addresses,
# 40-hex key fingerprints, SSH SHA256 fingerprints, private key blocks, and
# secret file types. Documentation values pass: RFC 5737 addresses and the
# RFC 7042 example MAC block (00:00:5e:00:53:xx), plus broadcast, all-zero
# and IPv4 multicast (01:00:5e:xx) MACs, which identify no device.
#
# Personal terms (real host names, a real domain, your own subnet) go in
# .githooks/leak-guard.local, one extended regex per line. That file is
# gitignored, so the deny list itself never gets published.
#
# A line containing the text leak-guard:allow is skipped. Use it sparingly.

set -u
mode="${1:-staged}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
local_list="$here/leak-guard.local"

oct='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
patterns=(
  "private IPv4|(^|[^0-9.])(10\.$oct|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.$oct\.$oct([^0-9.]|$)"
  "CGNAT/Tailscale IPv4|(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.$oct\.$oct([^0-9.]|$)"
  "MAC address|(^|[^0-9A-Fa-f:-])([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}([^0-9A-Fa-f:-]|$)"
  "40-hex fingerprint|(^|[^0-9A-Fa-f])[0-9A-Fa-f]{40}([^0-9A-Fa-f]|$)"
  "SSH fingerprint|SHA256:[A-Za-z0-9+/]{43}"
  "private key block|-----BEGIN ([A-Z]+ )*PRIVATE KEY-----"
)
if [[ -f "$local_list" ]]; then
  while IFS= read -r p || [[ -n "$p" ]]; do
    p="${p%$'\r'}"                  # Notepad saves CRLF; a stray \r would make every pattern unmatchable
    p="${p#$'\xef\xbb\xbf'}"           # same for a UTF-8 byte order mark on the first line
    [[ -z "$p" || "$p" == \#* ]] && continue
    patterns+=("local deny list|$p")
  done < "$local_list"
fi

# Values that look sensitive but are safe on purpose.
allow='leak-guard:allow|00:00:00:00:00:00|ff:ff:ff:ff:ff:ff|01[:-]00[:-]5[Ee][:-]|00[:-]00[:-]5[Ee][:-]00[:-]53[:-]|uses: [^ ]+@[0-9a-f]{40}'

# File names that never belong in this repo, whatever they contain.
bad_name='(^|/)(id_(rsa|ecdsa|ed25519)[^/]*|[^/]*\.(pem|key|pfx|p12|kdbx|ovpn|glas)|secrets\.log|cuairt\.json|\.env|leak-guard\.local)$'

hits=0
report() { printf 'leak-guard: %s: %s\n' "$1" "$2" >&2; hits=$((hits + 1)); }

scan() {  # $1 = label for output; stdin = lines to check
  local label="$1" line entry name rx
  while IFS= read -r line; do
    [[ "$line" =~ $allow ]] && continue
    for entry in "${patterns[@]}"; do
      name="${entry%%|*}"; rx="${entry#*|}"
      if [[ "$line" =~ $rx ]]; then report "$label" "$name: ${line:0:120}"; fi
    done
  done
}

if [[ "$mode" == "--all" ]]; then
  while IFS= read -r f; do
    [[ "$f" =~ $bad_name ]] && report "$f" "file type is never published"
    grep -Iq . "$f" 2>/dev/null || continue          # skip binary and empty files
    scan "$f" < "$f"
  done < <(git ls-files)
else
  while IFS= read -r f; do
    [[ "$f" =~ $bad_name ]] && report "$f" "file type is never published"
    # Process substitution, not a pipe: scan must run in this shell so its hit count survives.
    scan "$f" < <(git diff --cached -U0 --no-color --no-ext-diff -- "$f" \
      | grep -E '^\+' | grep -vE '^\+\+\+ ' | cut -c2-)
  done < <(git diff --cached --name-only --diff-filter=ACMR)
fi

if (( hits > 0 )); then
  echo "leak-guard: blocked ($hits finding(s)). Sanitize, or mark a deliberate example with leak-guard:allow." >&2
  exit 1
fi
exit 0
