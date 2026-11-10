#!/usr/bin/env bash

set -euo pipefail

ENV_FILES=(
    ".env-connector1"
    ".env-connector2"
    ".env-connectorcp"
)

for ENV_FILE in "${ENV_FILES[@]}"; do
    echo "=================================================="
    echo "Loading environment: ${ENV_FILE}"

    # Clear previously loaded variable
    unset ED_NODE_INSTANCE_NAME

    # Load environment
    source "./${ENV_FILE}"

    if [[ -z "${ED_NODE_INSTANCE_NAME:-}" ]]; then
        echo "ERROR: ED_NODE_INSTANCE_NAME is not defined in ${ENV_FILE}"
        exit 1
    fi

    echo "Connector: ${ED_NODE_INSTANCE_NAME}"

    echo "Stopping and removing volumes..."
    ./deploy.sh "${ED_NODE_INSTANCE_NAME}" down-v

    echo "Deploying..."
    ./deploy.sh "${ED_NODE_INSTANCE_NAME}"

    echo "Completed ${ED_NODE_INSTANCE_NAME}"
    echo
done

echo "All connectors deployed successfully."