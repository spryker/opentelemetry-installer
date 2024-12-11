#!/bin/bash

# Default values
project_namespace="Pyz"
IMAGE_FILE=""
INSTALL_FILE="config/install/docker.yml"
DEPLOY_FILE="deploy.yml"
BASE_IMAGE="volhovm/spryker-8.3-alpine-3.20"

# Function to display help
display_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --project-namespace <namespace>  Set the project namespace (default: Pyz)"
  echo "  --image-file <file>              Specify the image file (default: same as --deploy-file if not provided)"
  echo "  --install-file <file>            Path to the install configuration file (default: config/install/docker.yml)"
  echo "  --deploy-file <file>             Path to the deploy configuration file (default: deploy.yml)"
  echo "  --base-image <image>             Base Docker image (default: volhovm/spryker-8.3-alpine-3.20)"
  echo "  --help                           Display this help message"
  echo ""
  echo "Example:"
  echo "  $0 --project-namespace CustomNamespace --deploy-file custom-deploy.yml --base-image custom/image:tag"
  exit 0
}

# Check the status of the last command and exit if it failed
check_status() {
  if [[ $1 -ne 0 ]]; then
    echo "Error: $2"
    exit 1
  fi
}

# Process named parameters
while [[ $# -gt 0 ]]; do
  case $1 in
    --project-namespace)
      project_namespace="$2"
      shift 2
      ;;
    --image-file)
      IMAGE_FILE="$2"
      shift 2
      ;;
    --install-file)
      INSTALL_FILE="$2"
      shift 2
      ;;
    --deploy-file)
      DEPLOY_FILE="$2"
      shift 2
      ;;
    --base-image)
      BASE_IMAGE="$2"
      shift 2
      ;;
    --help)
      display_help
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

# Set IMAGE_FILE to DEPLOY_FILE if IMAGE_FILE is not explicitly provided
if [[ -z $IMAGE_FILE ]]; then
  IMAGE_FILE="$DEPLOY_FILE"
fi

# Display configuration
echo "Configuration summary:"
echo "======================"
echo "Project Namespace: $project_namespace"
echo "Image File: $IMAGE_FILE"
echo "Install File: $INSTALL_FILE"
echo "Deploy File: $DEPLOY_FILE"
echo "Base Image: $BASE_IMAGE"
echo "======================"

# Ask for confirmation
read -p "Do you want to proceed with this configuration? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Operation canceled by the user."
  exit 0
fi

# Check if the deploy file exists
if [[ ! -f "$DEPLOY_FILE" ]]; then
  echo "Error: File $DEPLOY_FILE does not exist."
  exit 1
fi

runSedCommand() {
    local content=$1
    local target=$2
    # Determine sed fix for macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$content" "$target"
    else
        sed -i "$content" "$target"
    fi

}
# Functions for file adjustments
adjustInstallFile() {
  local installFile="$1"
  local currentDir
  currentDir=$(pwd)

  if [[ ! -f "$installFile" ]]; then
    echo "Error: Install file $installFile does not exist."
    exit 1
  fi

  cmd=( -i -I4 '.sections.build.generate-open-telemetry.command = "vendor/bin/console open-telemetry:generate"' "$installFile" )
  echo "Execution command: docker run --rm -v $currentDir:/workdir mikefarah/yq --no-doc --indent 2 ${cmd[@]}"
  docker run --rm -v "$currentDir:/workdir" mikefarah/yq "${cmd[@]}"
  check_status $? "Failed to adjust install file: $installFile"
  echo "Install file updated successfully."
}

adjustDeployFile() {
    local deployFile="$1"
    local currentDir
    currentDir=$(pwd)
    cmd=( -i -I4 '.image.tag = "'$BASE_IMAGE'" | .image.php.enabled-extensions |= (.|select(. != null) + ["opentelemetry", "grpc", "protobuf"] | unique) // ["opentelemetry", "grpc", "protobuf"]' "$deployFile" )
    echo "Execution command: docker run --rm -v $currentDir:/workdir mikefarah/yq --no-doc --indent 2 ${cmd[@]}"
    docker run --rm -v "$currentDir:/workdir" mikefarah/yq "${cmd[@]}"
    check_status $? "Failed to adjust deploy file: $deployFile"
    echo "Deploy file updated successfully."
}

installDependencies() {
    # Boot the Docker SDK
    docker/sdk boot "$DEPLOY_FILE"
    check_status $? "Failed to boot the SDK with deploy file: $DEPLOY_FILE"

    # Install required dependencies
    docker/sdk cli composer require \
      "mismatch/opentelemetry-auto-redis:^0.3.0" \
      "open-telemetry/opentelemetry-auto-guzzle:^0.0.2" \
      "spryker/monitoring:^2.8.0" \
      "spryker/opentelemetry:^1.1.0" \
      "spryker/otel-elastica-instrumentation:^1.0.0" \
      "spryker/otel-rabbit-mq-instrumentation:^1.0.0" \
      "spryker/otel-propel-instrumentation:^1.0.0" --ignore-platform-reqs
    check_status $? "Failed to install required dependencies."
}

registerPlugins() {
    if [ -f "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php" ]; then
        # Check if the getMonitoringExtensions method exists
        if ! grep -q "function getMonitoringExtensions" "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"; then
                # If not present, add the method and the necessary use statements
                runSedCommand '/^}$/i\
        /**\
         * @return array<\\Spryker\\Service\\MonitoringExtension\\Dependency\\Plugin\\MonitoringExtensionPluginInterface>\
         */\
        protected function getMonitoringExtensions(): array\
        {\
            return [\
                new OpentelemetryMonitoringExtensionPlugin(),\
            ];\
        }
        ' src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php
        fi

        # Check if the plugins are already present
        if ! grep -q "OpentelemetryMonitoringExtensionPlugin" "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"; then

            # If not present, add them to the return array
            runSedCommand '/        return \[/a\
            \ \ \ \ new OpentelemetryMonitoringExtensionPlugin(),
            ' src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php
        fi

        if ! grep -Fq "use Spryker\\Service\\Opentelemetry\\Plugin\\OpentelemetryMonitoringExtensionPlugin;" "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"; then
            runSedCommand "/^namespace ${project_namespace//\\/\\\\}\\\\Service\\\\Monitoring;/a\\
use Spryker\\\\Service\\\\Opentelemetry\\\\Plugin\\\\OpentelemetryMonitoringExtensionPlugin;
            " "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"
        fi
    else
        # If the file doesn't exist, create it
        # Create the directory if it doesn't exist
        mkdir -p "src/$project_namespace/Service/Monitoring"
        cat <<EOF > "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"
<?php

/**
 * This file is part of the Spryker Suite.
 * For full license information, please view the LICENSE file that was distributed with this source code.
 */

namespace $project_namespace\Service\Monitoring;

use Spryker\Service\Monitoring\MonitoringDependencyProvider as SprykerMonitoringDependencyProvider;
use Spryker\Service\Opentelemetry\Plugin\OpentelemetryMonitoringExtensionPlugin;

class MonitoringDependencyProvider extends SprykerMonitoringDependencyProvider
{
    /**
     * @return array<\Spryker\Service\MonitoringExtension\Dependency\Plugin\MonitoringExtensionPluginInterface>
     */
    protected function getMonitoringExtensions(): array
    {
        return [
            new OpentelemetryMonitoringExtensionPlugin(),
        ];
    }
}
EOF
    fi

    # Check if the file exists
    if [ -f "src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php" ]; then
        # If the file exists, attempt to append the code to the $commands array
        if ! grep -q "OpentelemetryGeneratorConsole" "src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php"; then
            runSedCommand '/$commands = \[/a\
            new OpentelemetryGeneratorConsole(),
                ' src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php

                # Add the use statement if it doesn't already exist
                if ! grep -q "use Spryker\\Zed\\Opentelemetry\\Communication\\Plugin\\Console\\OpentelemetryGeneratorConsole;" "src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php"; then
                    runSedCommand "
                    /^namespace ${project_namespace//\\/\\\\}\\\\Zed\\\\Console;/a\\
use Spryker\\\\Zed\\\\Opentelemetry\\\\Communication\\\\Plugin\\\\Console\\\\OpentelemetryGeneratorConsole;" src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php
                fi
        fi
    fi

}

# Apply adjustments
adjustDeployFile "$IMAGE_FILE"
adjustInstallFile "$INSTALL_FILE"
registerPlugins
#installDependencies "$DEPLOY_FILE"

# Final message
echo "All tasks completed successfully. Please review your changes before deploying to other environments."
