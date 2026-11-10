#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -f "$tmp/functions.sh" "$tmp/root.token" "$tmp/token" "$tmp/identityhub-token" "$tmp/calls"; rmdir "$tmp"' EXIT

# Load only token maintenance functions, with isolated token files.
sed -n '/^maintain_service_token()/,/^# Main Monitoring Loop/p' \
    "$repo/launchers/vault-autounseal/autounseal.sh" |
    sed "s|/vault/|$tmp/|g" > "$tmp/functions.sh"
. "$tmp/functions.sh"

vault() {
    printf '%s %s\n' "$*" "${VAULT_TOKEN:-}" >> "$tmp/calls"
    case "$1 $2" in
        "token lookup")
            case "$VAULT_TOKEN" in
                valid) printf '{"data":{"ttl":100000}}' ;;
                expiring) printf '{"data":{"ttl":100}}' ;;
                *) return 1 ;;
            esac
            ;;
        "token renew")
            [ "${renew_fails:-false}" = false ]
            ;;
        "token create")
            [ "$VAULT_TOKEN" = root ] || return 1
            [ "${create_fails:-false}" = false ] || return 1
            if [ "${create_response+x}" = x ]; then
                printf '%s' "$create_response"
            else
                printf '{"auth":{"client_token":"replacement"}}'
            fi
            ;;
        *) return 1 ;;
    esac
}

reset_tokens() {
    printf 'root\n' > "$tmp/root.token"
    printf '%s\n' "$1" > "$tmp/token"
    printf '%s\n' "$2" > "$tmp/identityhub-token"
    : > "$tmp/calls"
    renew_fails=false
    create_fails=false
    unset create_response
}

reset_tokens valid invalid
regenerate_tokens
[ "$(cat "$tmp/token")" = valid ]
[ "$(cat "$tmp/identityhub-token")" = replacement ]
[ "$(grep -c 'token create' "$tmp/calls")" -eq 1 ]
echo "PASS: valid EDC token does not hide invalid IdentityHub token"

reset_tokens invalid invalid
regenerate_tokens
[ "$(cat "$tmp/token")" = replacement ]
[ "$(cat "$tmp/identityhub-token")" = replacement ]
[ "$(grep -c 'token create' "$tmp/calls")" -eq 2 ]
echo "PASS: both invalid tokens replaced independently"

reset_tokens valid valid
regenerate_tokens
! grep -q 'token create\|token renew' "$tmp/calls"
echo "PASS: healthy tokens remain unchanged"

reset_tokens expiring valid
regenerate_tokens
[ "$(cat "$tmp/token")" = expiring ]
grep -q 'token renew -increment=168h' "$tmp/calls"
! grep -q 'token create' "$tmp/calls"
echo "PASS: expiring token renewed without rotation"

reset_tokens expiring valid
renew_fails=true
regenerate_tokens
[ "$(cat "$tmp/token")" = replacement ]
echo "PASS: failed renewal replaces token"

reset_tokens invalid valid
create_fails=true
if regenerate_tokens; then
    echo "FAIL: token creation failure was ignored" >&2
    exit 1
fi
[ "$(cat "$tmp/token")" = invalid ]
grep -q 'token lookup -format=json valid' "$tmp/calls"
echo "PASS: creation failure is reported and other token still checked"

reset_tokens invalid valid
create_response='{"auth":{"client_token":null}}'
if regenerate_tokens; then
    echo "FAIL: missing token was accepted" >&2
    exit 1
fi
[ "$(cat "$tmp/token")" = invalid ]
echo "PASS: malformed response does not overwrite existing token"

reset_tokens invalid valid
create_response='{"auth":{"client_token":""}}'
if regenerate_tokens; then
    echo "FAIL: empty service token was accepted" >&2
    exit 1
fi
[ "$(cat "$tmp/token")" = invalid ]
echo "PASS: empty service token does not overwrite existing token"

reset_tokens valid valid
if maintain_service_token "$tmp/missing/token" Test; then
    echo "FAIL: token write failure was ignored" >&2
    exit 1
fi
echo "PASS: token write failure is reported"

reset_tokens valid valid
: > "$tmp/root.token"
if regenerate_tokens; then
    echo "FAIL: empty root token was accepted" >&2
    exit 1
fi
echo "PASS: empty root token fails explicitly"
