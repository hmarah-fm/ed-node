# ED-Node Demo Debugging & Troubleshooting Guide

## Issue 1: Connectors Only Receive 1 Credential Instead of 3 (`MembershipCredential` Only)

### Symptom
When querying IdentityHub credentials (`GET http://{{HOST}}:{{ConnectorPort}}/api/identity/v1alpha/credentials`), a connector (`connector2` or `connectorcp`) only returns 1 credential (`MembershipCredential`) instead of all 3 expected credentials:
1. `MembershipCredential`
2. `DataProcessorCredential`
3. `LegalPerson` (GAIA-X)

### Root Cause
During IdentityHub startup (`IdentityHubExtensionOdinS.start()`):
1. `MembershipCredential` is requested directly from `issuerservicevc` without requiring Keycloak.
2. `DataProcessorCredential` and `LegalPerson` require a JWT access token from Keycloak (`http://keycloak:8080/realms/unimaas/protocol/openid-connect/token`) using `grant_type=client_credentials` to extract participant roles.
3. If the Keycloak client for the connector does not have **Service accounts roles** enabled (or has a mismatched client secret in `.env-connector*`), Keycloak returns `401 Unauthorized`:
   ```json
   {"error":"unauthorized_client","error_description":"Client not enabled to retrieve service account"}
   ```
4. `obtainJWTKeyCloak()` returns an empty string `""`, causing `storeExtraScopeCredential()` and `storeGAIAXCredential()` to abort with `Invalid JWT format. Expected 3 parts, got 1`.

### Diagnostic Commands
```sh
# Check IdentityHub logs for Keycloak authentication and credential issuance
docker logs edc-ih-connector1 2>&1 | grep -i -E "CREDENTIAL-ISSUER|keycloak" -A 3 -B 1
docker logs edc-ih-connector2 2>&1 | grep -i -E "CREDENTIAL-ISSUER|keycloak" -A 3 -B 1
docker logs edc-ih-connectorcp 2>&1 | grep -i -E "CREDENTIAL-ISSUER|keycloak" -A 3 -B 1

# Verify stored credentials on each connector (ports: 9876=connector1, 9877=connector2, 9879=connectorcp)
for port in 9876 9877 9879; do
  echo "=== Port $port credential types ==="
  curl -s -H "x-api-key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=" \
    http://localhost:$port/api/identity/v1alpha/credentials | jq '[.[].verifiableCredential.credential.type]'
done
```

### Resolution
1. Open the Keycloak Admin Console (`http://localhost:5080`) and select the `unimaas` realm.
2. Go to **Clients** and select each connector client:
   - `did:web:edc-proxy-connector1%3A80:connector1`
   - `did:web:edc-proxy-connector2%3A80:connector2`
   - `did:web:edc-proxy-connectorcp%3A80:connectorcp`
3. Under **Settings** -> **Capability config**, ensure:
   - **Client authentication**: `ON`
   - **Service accounts roles**: `Checked`
4. Under **Credentials**, verify that the **Client Secret** matches `UNIMAAS_OIDC_IDP_CLIENT_SECRET` in `.env-connector1`, `.env-connector2`, and `.env-connectorcp`.
5. Restart the affected connector(s):
   ```sh
   ./deploy.sh connector2 restart
   ./deploy.sh connectorcp restart
   ```

---

## Issue 2: `502 Bad Gateway` (`401 Unauthorized: Token verification failed`) & `400 Bad Request` on Consumer Flows (`412-consumer-file asset` and `512-consumer-sparql asset`)

### Symptoms
- Executing `421-Get Connector1 Catalog` or `521-Get Connector2 Catalog` (`POST /api/management/v3/catalog/request`) from `connectorcp` returns `502 Bad Gateway`:
  ```json
  [{"message":"{\"@type\":\"dspace:CatalogError\",\"dspace:code\":\"401\",\"dspace:reason\":\"Unauthorized\"...}","type":"BadGateway"}]
  ```
- Provider connector logs (`edc-connector-connector1` / `edc-connector-connector2`) show:
  ```text
  DEBUG DSP: Incoming CatalogRequestMessage for class org.eclipse.edc.connector.controlplane.catalog.spi.Catalog process
  DEBUG Unauthorized: Token verification failed, Token verification failed
  DEBUG DSP: Service call failed: Unauthorized
  ```
- Subsequent Postman requests (`422-Initiate negotiation`, `424c-Initiate Transfer HttpProxy`, `522`, `524c`) fail with `400 Bad Request`.

### Root Causes
1. **Stale Issuer Private Key in Memory**:
   - Running `generateIssuerFiles-KeysDIDVault.sh` generates a new Ed25519 keypair (`issuerservicevc_private.pem`) and updates `did.json` on disk.
   - However, running `./deploy.sh issuerservicevc` (which executes `docker compose up -d`) does **not** restart the already-running `issuerservicevc` container when a bind-mounted file changes.
   - `issuerservicevc` (`main.py`) only loads `_private_key` into memory once at container startup, so it continued signing VCs with the **old** in-memory private key while `edc-proxy-issuerservicevc` served the **new** public key from `did.json`.
   - When `connector1` or `connector2` verified `connectorcp`'s Verifiable Presentation against `issuerservicevc`'s `did.json`, signature verification failed (`Token verification failed`).
2. **NGINX Upstream IP Caching on Container Restart**:
   - When `issuerservicevc` or `edc-ih-connector*` containers are restarted, Docker may assign new container IPs. If the NGINX proxy containers (`edc-proxy-*`) are not restarted *after* the upstream containers, NGINX forwards requests to stale IPs and returns `502 Bad Gateway`.
3. **Unset Postman Collection Variables (`400 Bad Request`)**:
   - Because `421` / `521` failed, Postman's post-response test script did not set `{{POLICY_ID_RDF}}`. Running `422` / `522` or `424c` / `524c` with empty `{{POLICY_ID_RDF}}` and `{{CONTRACT_AGREEMENT_ID_RDF}}` variables caused `400 Bad Request`.

### Diagnostic Commands
```sh
# 1. Check provider connector logs for DSP token verification errors
docker logs --tail 100 edc-connector-connector1 2>&1
docker logs --tail 100 edc-connector-connector2 2>&1
docker logs --tail 100 edc-connector-connectorcp 2>&1

# 2. Compare public key 'x' in DID documents against private keys on disk
echo "=== Check issuerservicevc private key vs did.json ==="
openssl pkey -in tests/issuerservice-vc/assets/keysPrivPub/issuerservicevc/issuerservicevc_private.pem -pubout -outform DER | tail -c 32 | base64 | tr '+/' '-_' | tr -d '='
echo ""
cat tests/issuerservice-vc/assets/dids/issuerservicevc/.well-known/did.json | jq -r '.verificationMethod[0].publicKeyJwk.x'

for p in connector1 connector2 connectorcp; do
  echo "=== Check $p ==="
  openssl pkey -in deployment/assets/keysPrivPub/$p/${p}_private.pem -pubout -outform DER | tail -c 32 | base64 | tr '+/' '-_' | tr -d '='
  echo ""
  cat deployment/assets/dids/$p/.well-known/did.json | jq -r '.verificationMethod[0].publicKeyJwk.x'
done

# 3. Check Vault JWK keys (secret/key-1) for each connector
for p in connector1 connector2 connectorcp; do
  echo "=== Vault key-1 in $p ==="
  TOKEN=$(docker exec edc-vault-$p cat /vault/token)
  docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN="$TOKEN" edc-vault-$p vault kv get -field=content secret/key-1
  echo ""
done

# 4. Check when issuerservicevc container started vs when keys were generated on disk
docker inspect issuerservicevc --format '{{.State.StartedAt}}'
ls -l --full-time tests/issuerservice-vc/assets/keysPrivPub/issuerservicevc/ tests/issuerservice-vc/assets/dids/issuerservicevc/.well-known/

# 5. Verify whether a VC signature matches the issuer key on disk
RAW_VC=$(curl -s -H "x-api-key: c3VwZXItdXNlcg==.c3VwZXItc2VjcmV0LWtleQo=" http://localhost:9879/api/identity/v1alpha/credentials | jq -r '.[0].verifiableCredential.rawVc')
docker exec issuerservicevc python3 -c "
import jwt
from cryptography.hazmat.primitives import serialization
with open('/app/keys/issuer_private.pem', 'rb') as f:
    priv = serialization.load_pem_private_key(f.read(), password=None)
pub = priv.public_key()
jwt.decode('$RAW_VC', pub, algorithms=['EdDSA'], options={'verify_aud': False})
print('SIGNATURE VALID WITH DISK KEY')
"

# 6. Verify Fuseki SPARQL endpoint reachability from connector2 container
docker exec edc-connector-connector2 curl -s -o /dev/null -w "%{http_code}\n" \
  -u admin:mypassword \
  --data-urlencode "query=CONSTRUCT { ?s ?p ?o .} WHERE { ?s ?p ?o .}" \
  http://172.17.0.1:3032/provider/query
```

### Resolution Commands
Restart the containers **in dependency order** so `issuerservicevc` reloads its private key, its NGINX proxy updates its upstream IP, the IdentityHubs re-issue all 3 VCs signed with the current key, and the connector NGINX proxies refresh their upstream IPs:

```sh
# 1. Restart issuerservicevc and its nginx proxy so the in-memory key matches did.json
docker restart issuerservicevc
sleep 3
docker restart edc-proxy-issuerservicevc

# 2. Restart IdentityHub containers to re-issue and replace the 3 VCs with the current signature
docker restart edc-ih-connector1 edc-ih-connector2 edc-ih-connectorcp
sleep 12

# 3. Restart connector nginx proxies so they resolve the current container IPs
docker restart edc-proxy-connector1 edc-proxy-connector2 edc-proxy-connectorcp
sleep 3
```

### Verification Commands
```sh
# Verify 421-Get Connector1 Catalog from ConnectorCP
curl -i -s -X POST "http://localhost:9879/api/management/v3/catalog/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": {
        "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    },
    "@type": "CatalogRequest",
    "protocol": "dataspace-protocol-http",
    "counterPartyAddress": "http://edc-connector-connector1:8082/api/dsp",
    "counterPartyId": "did:web:edc-proxy-connector1%3A80:connector1",
    "querySpec": {
        "offset": 0,
        "limit": 50
    }
}'

# Verify 521-Get Connector2 Catalog from ConnectorCP
curl -i -s -X POST "http://localhost:9879/api/management/v3/catalog/request" \
  -H "Content-Type: application/json" \
  -H "x-api-key: password" \
  -d '{
    "@context": {
        "@vocab": "https://w3id.org/edc/v0.0.1/ns/"
    },
    "@type": "CatalogRequest",
    "protocol": "dataspace-protocol-http",
    "counterPartyAddress": "http://edc-connector-connector2:8082/api/dsp",
    "counterPartyId": "did:web:edc-proxy-connector2%3A80:connector2",
    "querySpec": {
        "offset": 0,
        "limit": 50
    }
}'
```

Once both catalog requests return `200 OK`, execute the Postman requests in order (`421` -> `422` -> `423` -> `424c` -> `425` -> `426` -> `427` -> `428` and `521` -> `522` -> `523` -> `524c` -> `525` -> `526` -> `527` -> `528`) so Postman populates the collection variables at each step.

