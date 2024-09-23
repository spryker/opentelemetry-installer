#!/bin/bash

# Prerequisites: jq tool should be installed in the system.

project_namespace=${1:-Pyz}

wget https://raw.githubusercontent.com/spryker/opentelemetry/master/otel-autoload-example.php -O otel-autoload.php

dependencies=(
  "open-telemetry/sdk:^1.0"
  "ext-opentelemetry:*"
  "mismatch/opentelemetry-auto-redis:^0.3.0"
  "open-telemetry/exporter-otlp:^1.0"
  "open-telemetry/gen-otlp-protobuf:^1.1"
  "open-telemetry/opentelemetry-auto-guzzle:^0.0.2"
  "spryker/monitoring:^2.8.0"
  "open-telemetry/transport-grpc:^1.0"
  "ext-grpc:*"
  "spryker/opentelemetry:^0.1.1"
  "spryker/otel-backoffice-application-instrumentation:^0.1.1"
  "spryker/otel-console-instrumentation:^0.1.1"
  "spryker/otel-elastica-instrumentation:^0.1.0"
  "spryker/otel-rabbit-mq-instrumentation:^0.1.0"
  "spryker/otel-propel-instrumentation:^0.1.0"
  "spryker/otel-application-instrumentation:^0.1.1"
)

if [ -f vendor/spryker/spryker/Bundles/GlueApplication/src/Spryker/Glue/GlueApplication/Bootstrap/GlueBootstrap.php ] || [ -f vendor/spryker/glue-application/src/Spryker/Glue/GlueApplication/Bootstrap/GlueBootstrap.php ] || [ -f "src/$project_namespace/Glue/GlueApplication/Bootstrap/GlueBootstrap.php" ]; then
  dependencies+=("spryker/otel-glue-application-instrumentation:^0.1.0")
fi

if [ -f vendor/spryker/spryker/Bundles/MerchantPortalApplication/src/Spryker/Zed/MerchantPortalApplication/Communication/Bootstrap/MerchantPortalBootstrap.php ] || [ -f vendor/spryker/merchant-portal-application/src/Spryker/Zed/MerchantPortalApplication/Communication/Bootstrap/MerchantPortalBootstrap.php ] || [ -f "src/$project_namespace/Zed/MerchantPortalApplication/Communication/Bootstrap/MerchantPortalBootstrap.php" ]; then
    dependencies+=("spryker/otel-merchant-portal-application-instrumentation:^0.1.0")
fi

if [ -f vendor/spryker/spryker-shop/Bundles/ShopApplication/src/SprykerShop/Yves/ShopApplication/Bootstrap/YvesBootstrap.php ] || [ -f vendor/spryker-shop/shop-application/src/SprykerShop/Yves/ShopApplication/Bootstrap/YvesBootstrap.php ] || [ -f "src/$project_namespace/Yves/ShopApplication/YvesBootstrap.php" ]; then
    dependencies+=("spryker-shop/otel-shop-application-instrumentation:^0.1.0")
fi

for dependency in "${dependencies[@]}"; do
  package_name=$(echo "$dependency" | cut -d':' -f1)
  package_version=$(echo "$dependency" | cut -d':' -f2)

  jq --arg package "$package_name" --arg version "$package_version" '.require[$package] = $version' composer.json > composer.json.tmp && mv composer.json.tmp composer.json
done

# Ensure 'autoload' exists and is an object
jq 'if .autoload == null then .autoload = {} else . end' composer.json > composer.json.tmp && mv composer.json.tmp composer.json

# Ensure 'autoload.files' exists and is an array
jq 'if .autoload.files == null then .autoload.files = [] else . end' composer.json > composer.json.tmp && mv composer.json.tmp composer.json

# Ensure 'autoload."psr-4"' exists and is an object
jq 'if .autoload."psr-4" == null then .autoload."psr-4" = {} else . end' composer.json > composer.json.tmp && mv composer.json.tmp composer.json

if ! jq -e '.autoload.files | any(. == "otel_autoload.php")' composer.json > /dev/null; then
  # If not present, add it
  jq '.autoload.files += ["otel_autoload.php"]' composer.json > composer.json.tmp && mv composer.json.tmp composer.json
fi

# Check if PSR-4 autoload entries already exist
if ! jq -e '.autoload."psr-4" | has("OtelUpdater\\")' composer.json > /dev/null; then
  jq '.autoload."psr-4" += {"OtelUpdater\\": "src/Otel/"}' composer.json > composer.json.tmp && mv composer.json.tmp composer.json
fi

if ! jq -e '.autoload."psr-4" | has("OpenTelemetry\\Contrib\\Instrumentation\\Symfony\\")' composer.json > /dev/null; then
  jq '.autoload."psr-4" += {"OpenTelemetry\\Contrib\\Instrumentation\\Symfony\\": "src/"}' composer.json > composer.json.tmp && mv composer.json.tmp composer.json
fi

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
            \new OpentelemetryGeneratorConsole(),
            ' "src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php"

            # Add the use statement if it doesn't already exist
            if ! grep -q "use Spryker\\Zed\\Opentelemetry\\Communication\\Plugin\\Console\\OpentelemetryGeneratorConsole;" "src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php"; then
                sed -i '' "
                /^namespace ${project_namespace//\\/\\\\}\\\\Zed\\\\Console;/a\\
use Spryker\\\\Zed\\\\Opentelemetry\\\\Communication\\\\Plugin\\\\Console\\\\OpentelemetryGeneratorConsole;" "src/$project_namespace/Zed/Console/ConsoleDependencyProvider.php"
            fi
    fi
fi

composer update
