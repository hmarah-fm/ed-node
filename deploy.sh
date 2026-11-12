#!/usr/bin/env bash
#
# This script manages a Docker-Compose instance.
# It takes the instance name and an optional mode for the 'down' command.
#
# Usage: $0 <instance_name> [mode]
#
# Available modes:
#   build_up (default): Only builds and brings up containers, skipping the 'down' command.
#   down-v: Executes 'docker compose down -v'.
#   fromzero: Executes 'docker compose down -v', 'docker compose build' and 'docker compose up -d'.
#   restart: Executes 'docker compose restart'.
#   stop: Executes 'docker compose stop'.

set -e

# Read command-line parameters
INSTANCE_NAME=$1
MODE=$2

# Show help if requested
if [[ "$INSTANCE_NAME" == "-h" || "$INSTANCE_NAME" == "--help" ]]; then
  echo "Usage: $0 <instance_name> [mode]"
  echo
  echo "Manages a Docker-Compose instance by giving it a unique project name."
  echo "The script performs the following actions:"
  echo "1. Exports variables from the '.env-<instance_name>' file."
  echo "2. Generates a 'docker-compose-<instance_name>.yml' file from a template."
  echo "3. Generates a 'nginx--<instance_name>.conf' file from a template."
  echo "4. Executes 'docker compose down' command based on the specified mode, affecting only the specified project."
  echo "5. Builds the images for the specified project."
  echo "6. Lifts the containers in 'detached' mode for the specified project."
  echo
  echo "Parameters:"
  echo "  <instance_name>  The name of the instance to manage. This will be used as the Docker project name."
  echo "                   Required."
  echo "  [mode]           Optional: If not specified, 'build_up' mode is used."
  echo
  echo "Mode valid values:"
  echo "  build_up (or blank)   Skips the 'down' command completely, only performing 'build' and 'up'."
  echo "  down-v                Stops services and removes containers and volumes for the project."
  echo "                        Equivalent to 'docker compose down -v'."
  echo "  fromzero              Stops services and removes containers and volumes for the project."
  echo "                        Equivalent to 'docker compose down -v', finally performing 'build' and 'up'."
  echo "  restart               Restarts services (containers) for the project."
  echo "                        Equivalent to 'docker compose restart'."
  echo "  stop                  Stops services (containers) for the project."
  echo "                        Equivalent to 'docker compose stop'."
  echo
  echo "Examples:"
  echo "  $0 instance_name1"
  echo "  $0 instance_name1 build_up"
  echo "  $0 instance_name1 down-v"
  echo "  $0 instance_name1 fromzero"
  echo "  $0 instance_name1 restart"
  echo "  $0 instance_name1 stop"

  exit 0
fi

# Validate that the instance name was provided
if [ -z "$INSTANCE_NAME" ]; then
  echo "Error: The instance name is required."
  echo "Usage: $0 <instance_name> [mode]"
  echo "For more information, use: $0 -h"
  exit 1
fi

# Instance-specific .env file
ENV_FILE=".env-${INSTANCE_NAME}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: The file $ENV_FILE does not exist."
  exit 1
fi

# Export variables from the .env file
set -o allexport
source "$ENV_FILE"
set +o allexport

# Generate instance-specific docker-compose.yml from the template
echo "Generating docker-compose-${INSTANCE_NAME}.yml..."
envsubst < docker-compose-template.yml > docker-compose-${INSTANCE_NAME}.yml

# Generate instance-specific nginx.conf from the template
echo "Generating nginx-${INSTANCE_NAME}.conf..."
#envsubst < deployment/nginx/nginx-template.conf > deployment/nginx/nginx-${INSTANCE_NAME}.conf
envsubst '$ED_NODE_INSTANCE_NAME' < deployment/nginx/nginx-template.conf > deployment/nginx/nginx-${INSTANCE_NAME}.conf

# Determine which 'down' command to run based on the mode
case "$MODE" in
  build_up|"")
    echo "Skipping the 'down' step..."
    ;;
  down-v)
    echo "Executing 'down -v' (down-v mode)..."
    docker compose --project-name "$INSTANCE_NAME" --env-file "$ENV_FILE" -f docker-compose-${INSTANCE_NAME}.yml down -v
    echo "Process completed for instance '$INSTANCE_NAME'!"
    exit 0
    ;;
  fromzero)
    echo "Executing 'down -v' (fromzero mode)..."
    docker compose --project-name "$INSTANCE_NAME" --env-file "$ENV_FILE" -f docker-compose-${INSTANCE_NAME}.yml down -v
    ;;  
  restart)
    echo "Executing 'restart' (restart mode)..."
    docker compose --project-name "$INSTANCE_NAME" --env-file "$ENV_FILE" -f docker-compose-${INSTANCE_NAME}.yml restart
    echo "Process completed for instance '$INSTANCE_NAME'!"
    exit 0
    ;;
  stop)
    echo "Executing 'stop' (stop mode)..."
    docker compose --project-name "$INSTANCE_NAME" --env-file "$ENV_FILE" -f docker-compose-${INSTANCE_NAME}.yml stop
    echo "Process completed for instance '$INSTANCE_NAME'!"
    exit 0
    ;;
  *)
    echo "Invalid mode: $MODE"
    echo "Available modes: build_up, down-v, fromzero, restart, stop"
    echo "For more information, use: $0 -h"
    exit 1
    ;;
esac

# Build services
echo "Building images..."
#docker compose --project-name "$INSTANCE_NAME" --env-file "$ENV_FILE" -f docker-compose-${INSTANCE_NAME}.yml build
docker compose --project-name "$INSTANCE_NAME" --env-file "$ENV_FILE" -f docker-compose-${INSTANCE_NAME}.yml build

# Lift services
echo "Lifting services..."
#docker compose --project-name "$INSTANCE_NAME" --env-file "$ENV_FILE" -f docker-compose-${INSTANCE_NAME}.yml up -d
docker compose --project-name "$INSTANCE_NAME" --env-file "$ENV_FILE" -f docker-compose-${INSTANCE_NAME}.yml up -d

# NGINX resolves connector upstream addresses at startup; refresh it after a connector is recreated.
docker compose --project-name "$INSTANCE_NAME" --env-file "$ENV_FILE" -f docker-compose-${INSTANCE_NAME}.yml restart edc-proxy

echo "Process completed for instance '$INSTANCE_NAME'!"