# ISSUERSERVICE-VC - Deployment Steps

# 0 - Configuration

Configure `.env` file, define the host (`BASE_HOST`), exposed port (`NGINX_EXPOSED_PORT`) and instance name (`ISSUERSERVICEVC_INSTANCE_NAME`).

## 1 - Create Private/Public Key, DID & Vault Config File

To deploy the `issuerservice-vc`, you must first create the private and public keys for the DID document. This folder offers a script (`generateIssuerFiles-KeysDIDVault`) to generate test keys.

```sh
cd tests/issuerservice-vc;
./generateIssuerFiles-KeysDIDVault.sh <instanceName> <issuerServiceDIDHost>:<issuerServiceDIDPort>;
# ex: ./generateIssuerFiles-KeysDIDVault.sh issuerservicevc edc-proxy-issuerservicevc:80
```
Where:

- <instanceName>: Instance name.
- <edNodeDIDHost:edNodeDIDPort>: host & port where DID related to the ED-Node can be resolved. (`ISSUERSERVICEVC_HOST`:`ISSUERSERVICEVC_DID_PORT`)

The generator replaces the signing keypair. Do not rerun it merely to repair a
catalog authentication error. The DID's `publicKeyJwk.x` must match the public
key derived from the issuer's current private key; restarting cannot repair a
mismatch already present on disk. Existing VCs may be present and retrievable
but still fail signature validation against an incorrect DID key.
See [catalog authentication troubleshooting](../debuggin.md#issue-2-502-bad-gateway-401-unauthorized-token-verification-failed--400-bad-request-on-consumer-flows-412-consumer-file-asset-and-512-consumer-sparql-asset).

Running the script should create two new folders, `assets` and `vault`, with the following contents:

```
assets/
├── dids/
│   ├── issuerservicevc/
│   │   └── .well-known/
│   │       └── did.json
└── keysPrivPub/
        └── issuerservicevc/
            ├── issuerservicevc_private.pem
            └── issuerservicevc_public.pem
vault/
     └── issuerservicevc/
        └── vault-issuerservicevc-config.json
```

# 2 - Deploy

Deploy with:

```sh
cd tests/issuerservice-vc/;
./deploy.sh <instanceName> or ./deploy.sh <instanceName> build_up
#For instance: ./deploy.sh issuerservicevc
```

**NOTE:** For simulating `docker compose down -v` executes:
```sh
./deploy.sh <instanceName> down-v
#For instance: ./deploy.sh issuerservicevc down-v
```

**NOTE:** For simulating `docker compose down -v; docker compose build; docker compose up -d` executes:
```sh
./deploy.sh <instanceName> fromzero
#For instance: ./deploy.sh issuerservicevc fromzero
```

**NOTE:** For simulating `docker compose restart` executes:
```sh
./deploy.sh <instanceName> restart
#For instance: ./deploy.sh issuerservicevc restart
```

**NOTE:** For simulating `docker compose stop` executes:
```sh
./deploy.sh <instanceName> stop
#For instance: ./deploy.sh issuerservicevc stop
```

# 3 - LOGS Monitor

```sh
sleep 4; docker logs -f issuerservicevc
```

# 4 - Testing


## 4.1 - DID Resolution is working

```sh
curl http://localhost:9878/issuerservicevc/.well-known/did.json
```

## 4.2 - IssuerService-VC API

### Check Health
```sh
curl http://localhost:9878/api/v1/health
```

### Info

```sh
curl http://localhost:9878/api/v1/info
```

### Endpoints

Obtain "verifiableCredential.rawVc"

```sh
curl -X POST http://localhost:9878/api/v1/sign-credential \
  -H "Content-Type: application/json" \
  -d '{
  "participantDid": "did:web:localhost%3A9876:connector1",
  "credential": {
    "@context": [
      "https://www.w3.org/2018/credentials/v1",
      "https://w3id.org/security/suites/jws-2020/v1",
      "https://www.w3.org/ns/did/v1",
      {
        "unimaas-credentials": "https://w3id.org/unimaas/credentials/",
        "contractVersion": "unimaas-credentials:contractVersion",
        "level": "unimaas-credentials:level"
      }
    ],
    "id": "http://org.yourdataspace.com/credentials/2347",
    "type": [
      "VerifiableCredential",
      "DataProcessorCredential"
    ],
    "issuer": "did:web:localhost%3A9878:issuerservicevc",
    "issuanceDate": "2023-08-18T00:00:00Z",
    "credentialSubject": {
      "id": "did:web:localhost%3A9876:connector1",
      "contractVersion": "1.0.0",
      "level": "processing"
    }
  }
}'
```

Obtain full signed Verifiable Credential:

```sh
curl -X POST http://localhost:9878/api/v1/issue-credential \
  -H "Content-Type: application/json" \
  -d '{
  "participantDid": "did:web:localhost%3A9876:connector1",
  "holderDid": "did:web:localhost%3A9876:connector1",
  "credential": {
    "@context": [
      "https://www.w3.org/2018/credentials/v1",
      "https://w3id.org/security/suites/jws-2020/v1",
      "https://www.w3.org/ns/did/v1",
      {
        "unimaas-credentials": "https://w3id.org/unimaas/credentials/",
        "contractVersion": "unimaas-credentials:contractVersion",
        "level": "unimaas-credentials:level"
      }
    ],
    "id": "http://org.yourdataspace.com/credentials/2347",
    "type": [
      "VerifiableCredential",
      "DataProcessorCredential"
    ],
    "issuer": "did:web:localhost%3A9878:issuerservicevc",
    "issuanceDate": "2023-08-18T00:00:00Z",
    "credentialSubject": {
      "id": "did:web:localhost%3A9876:connector1",
      "contractVersion": "1.0.0",
      "level": "processing"
    }
  }
}'
```

Obtain full signed Verifiable Credential (GAIA-X 22.06/24.11):

```sh
curl -X POST http://localhost:9090/api/v1/issue-gaiax-credential-jwt \
  -H "Content-Type: application/json" \
  -d '{
    "participantDid": "did:web:localhost%3A7083",
    "legalName": "Mi Empresa Test SL",
    "countryCode": "ES",
    "vatNumber": "ESB12345678",             //OPTIONAL
    "addressCode": "ES-M",                  //OPTIONAL
    "streetAddress": "Calle Ejemplo 123",   //OPTIONAL
    "postalCode": "28001",                   //OPTIONAL
    "roles": ["partner","secure-administrator"]
  }'
```

Expected response:

```json
{
  "id": "uuid...",
  "participantContextId": "did:web:localhost%3A7083",
  "timestamp": 1736524800000,
  "issuerId": "did:web:localhost%3A9876:issuerservicevc",
  "holderId": "did:web:localhost%3A7083",
  "state": 500,
  "verifiableCredential": {
    "format": "VC1_0_JWT",
    "rawVc": "...",
    "credential": {
      "@context": [...],
      "id": "...",
      "type": ["VerifiableCredential", "LegalPerson"],
      "credentialSubject": {...},
      "credentialSchema": [...],
      "issuer": "...",
      "issuanceDate": "...",
      "expirationDate": "..."
    }
  }
}
```
