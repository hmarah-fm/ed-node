# 2026-09 review demo

## Set up
- keycloak clients
  - did:web:edc-proxy-connector1%3A80:connector1
    - secret EqdQ8TRr4AbROpFrXDr3a4r8pEzQQjN7
  - did:web:edc-proxy-connector2%3A80:connector2
    - secret 5UBhXDOzRvQpu3CiUPXNTn2tXxEAqlje
  - did:web:edc-proxy-connectorcp%3A80:connectorcp
    - secret: 6QU85OYXvSIu2gqs4p9c548nnUWxL5tM  
- 3 ed-nodes
  - connector1
  - connector2
  - connectorcp
- network
  - internal ports
    - credentilas: 7091
    - identity: 7092
    - management: 8081
    - dsp: 8082
    - catalog: 8084
    - public: 10011
  - issuerservice
    - ports 7000:80
  - connector1
    - ports 9876:80
  - connector2
    - ports 9877:80
  - connectorcp
    - ports 9879:80
- postgres
  - db: edc
  - user: edc_user
  - password: edc_password    

## Datasets

Connector1: 
- file based:
  - internal processes (downstream or'after)
  - file `/shared-storage/demo/dataset_2/subgraph_pc3pc4_internal.ttl`

Connector2:
- triple store based:
  - external processes (upstream or before)
  - store: `http://localhost:3032/provider/query`
  - query: `PREFIX sc: <http://example.com/MSCOnto#> CONSTRUCT { ?s ?p ?o .} WHERE { ?s ?p ?o .}`  

For the Postman collection, set `Connector2Fuseki` to `3032` and set `FusekiUsername` / `FusekiPassword` for the status check. The SPARQL asset endpoint must be reachable from Connector 2; `172.17.0.1` is the Docker host gateway in the current setup. Set each `.env-connector*` `NGINX_PUBLIC_HOST` to `localhost` for same-machine Postman downloads, or to a host/IP reachable by remote consumers.

## Run

### Initialize the edc-rdf git submodule

```bash
git submodule update --init extensions/edc-rdf
```

### Postgres

```sh
psql edc edc_user
```

### Start the Issuer Service

```sh
cd tests/issuerservice-vc;

. .env

. ./generateIssuerFiles-KeysDIDVault.sh ${ISSUERSERVICEVC_INSTANCE_NAME} ${ISSUERSERVICEVC_HOST}:${ISSUERSERVICEVC_DID_PORT};

. ./deploy.sh $ISSUERSERVICEVC_INSTANCE_NAME 
```

### Start/Stop/Restart a connector

```sh
# load the env vars for the targeted connector
. .env-connector1
. .env-connector2
. .env-connectorcp

# generate the keys for the targeted connector
. ./generateEDNodeFiles-KeysDIDVault.sh ${ED_NODE_INSTANCE_NAME} ${BASE_HOST}:${NGINX_INTERNAL_PORT};

# start/stop the connector
. ./deploy.sh ${ED_NODE_INSTANCE_NAME} 
. ./deploy.sh ${ED_NODE_INSTANCE_NAME} restart
. ./deploy.sh ${ED_NODE_INSTANCE_NAME} down-v
```

```sh
# load the env vars for the targeted connector
source ./.env-connector1
source ./.env-connector2
source ./.env-connectorcp

# generate the keys for the targeted connector
. ./generateEDNodeFiles-KeysDIDVault.sh ${ED_NODE_INSTANCE_NAME} ${BASE_HOST}:${NGINX_INTERNAL_PORT};

# start/stop the connector
./deploy.sh ${ED_NODE_INSTANCE_NAME} 
./deploy.sh ${ED_NODE_INSTANCE_NAME} restart
./deploy.sh ${ED_NODE_INSTANCE_NAME} down-v
```


Check:
- the postman collection 
  - request `Get Connector Credentials`
    - expected: 3 credentials
  - request `Get Connector DID`
    - expected: 1 DID

### Create a dataset in a Provider Connector 1/2

Create an RDF file-based asset in Connector1:
- open the postmam folder `Demo/ConnectorX/400-Request-RDF-Service-Flow (File Asset)/410-provider-connector (file asset)`
  - request `411-Create RDF Service Asset File`
  - request `412 Create Policy (Allow ALL)`
  - request `414-Create "allow-all" for RDFService`

Check:  
- consult Connector1 catalog internally (by connector1 organization)
  - request `Connector1/Get Connector1 Assets`
    - note the dataAddress with data physical locatin
    - note the public properties, with msc metadata

### Get a dataset from a Consumer (central platform) connector

Consume the asset
- open the postman folder `ConnectorCP/412-consumer-file asset`
  - request `421-Get Connector1 Catalog`
    - note the dataset recently created, with its public metadata properties
  - request `422-Initiate negotiation`
  - request `423-Get Contract Negotiations`
    - note the aggreement
  - request `424c-Initiate Transfer HttpProxy`  
  - request `425-Get transfer processes`
  - request `426-Get cached EDRs`
    - `EDR` is 'external data reference'
  - request `427-Get EDR DataAddress for TransferId`  
  - request `428-Download Data from Public API`
    - note: RDF data is received: OK




