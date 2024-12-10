#!/bin/bash

# Prerequisites: yq tool should be installed in the system.

project_namespace=${1:-Pyz}

# Path to the target deploy YAML file
DEPLOY_FILE=${2:-"deploy.yml"}

# Check if the file exists
if [[ ! -f "$DEPLOY_FILE" ]]; then
  echo "Error: File $DEPLOY_FILE does not exist."
  exit 1
fi

# Check if the yq command is available
if ! command -v yq &> /dev/null; then
  echo "Error: 'yq' command not found. Please install it before running this script. E.g. brew install yq"
  exit 1
fi

yq -i '.image.tag = "volhovm/spryker-8.3-alpine-3.20"' "$DEPLOY_FILE"
yq -i '.image.php.enabled-extensions += "opentelemetry"' "$DEPLOY_FILE"
yq -i '.image.php.enabled-extensions += "grpc"' "$DEPLOY_FILE"
yq -i '.image.php.enabled-extensions += "protobuf"' "$DEPLOY_FILE"

docker/sdk cli composer require "mismatch/opentelemetry-auto-redis:^0.3.0" "open-telemetry/opentelemetry-auto-guzzle:^0.0.2" "spryker/monitoring:^2.8.0" "spryker/opentelemetry:^1.1.0" "spryker/otel-elastica-instrumentation:^1.0.0" "spryker/otel-rabbit-mq-instrumentation:^1.0.0" "spryker/otel-propel-instrumentation:^1.0.0" --ignore-platform-reqs

if [ -f "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php" ]; then
    # Check if the getMonitoringExtensions method exists
        if ! grep -q "function getMonitoringExtensions" "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"; then
            # If not present, add the method and the necessary use statements
            sed -i '' '/^}$/i\
    /**\
     * @return array<\\Spryker\\Service\\MonitoringExtension\\Dependency\\Plugin\\MonitoringExtensionPluginInterface>\
     */\
    protected function getMonitoringExtensions(): array\
    {\
        return [\
            new OpentelemetryMonitoringExtensionPlugin(),\
        ];\
    }
    ' "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"
        fi

    # Check if the plugins are already present
    if ! grep -q "OpentelemetryMonitoringExtensionPlugin" "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"; then

        # If not present, add them to the return array
        sed -i '' '/        return \[/a\
        \ \ \ \ \new OpentelemetryMonitoringExtensionPlugin(),
        ' "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"
    fi

    if ! grep -q "use Spryker\\Service\\Opentelemetry\\Plugin\\OpentelemetryMonitoringExtensionPlugin;" "src/$project_namespace/Service/Monitoring/MonitoringDependencyProvider.php"; then
        sed -i '' "/^namespace ${project_namespace//\\/\\\\}\\\\Service\\\\Monitoring;/a\\
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
            sed -i '' '/$commands = \[/a\
            new OpentelemetryGeneratorConsole(),
            ' "src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php"

            # Add the use statement if it doesn't already exist
            if ! grep -q "use Spryker\\Zed\\Opentelemetry\\Communication\\Plugin\\Console\\OpentelemetryGeneratorConsole;" "src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php"; then
                sed -i '' "
                /^namespace ${project_namespace//\\/\\\\}\\\\Zed\\\\Console;/a\\
use Spryker\\\\Zed\\\\Opentelemetry\\\\Communication\\\\Plugin\\\\Console\\\\OpentelemetryGeneratorConsole;" "src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php"
            fi
    fi
fi


# Path to the target YAML file
INSTALL_FILE=${3:-"config/install/docker.yml"}

# Check if the file exists
if [[ ! -f "$INSTALL_FILE" ]]; then
  echo "Error: File $INSTALL_FILE does not exist."
  exit 1
fi

# Check if the yq command is available
if ! command -v yq &> /dev/null; then
  echo "Error: 'yq' command not found. Please install it before running this script. E.g. brew install yq"
  exit 1
fi

# Add the new section under `sections.build`
yq -i '.sections.build.generate-open-telemetry.command = "vendor/bin/console open-telemetry:generate"' "$INSTALL_FILE"



echo "All done! Review your changes before pushing to other envs. Run docker/sdk boot $DEPLOY_FILE first if you want to check everything locally in order to enable required extensions"
