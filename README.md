This guide explains how to use the installer script to integrate OpenTelemetry into your project.

### Script Overview

The otel_integrator.sh script automates the integration of OpenTelemetry into a project. It updates deploy and install files, wires required plugins and install required packages.

**Parameters**

- --project-namespace:
    - Default: Pyz
    - Specifies the project namespace. Will be used to put required plugins under the proper namespace.

- --deploy-file:
    - Default: deploy.yml
    - Specifies the name of the deploy configuration file. This will be used to enabled required PHP extensions and boot application after.

- --image-file:
    - Default: same as --deploy-file
    - In cases when your PHP image information is located in the different file, you can specify it via this param. If no value provided, script assumes that deploy file has all required fields.

- --install-file:
    - Default: config/install/docker.yml
    - Specifies the install configuration file to update. This is needed in order to re-generate hook files on each install/deploy.

- --base-image:
    - Default: spryker/php:8.3-alpine3.20-otel
    - Allows you to specify your custom PHP image to use. Make sure that it has required extensions ("opentelemetry", "grpc", "protobuf") included.

### Prerequisites

- docker

### Execution Steps

- Copy the otel_integrator.sh script to the root directory of your project:

  - Run the script with the required parameters (or use defaults):
    

      ./otel_integrator.sh --project-namespace [PROJECT_NAMESPACE] --deploy-file [DEPLOY_FILE_NAME] --install-file [INSTALL_SCRIPT_NAME]
  

  Example:

      ./otel_integrator.sh --project-namespace  Pyz --deploy-file deploy.yml 

The script will modify the specified files as needed to integrate OpenTelemetry.

### Post-Script Review

After running the script:

- Verify the Deploy File:
    - Review changes in the deploy (image) file (deploy.yml by default) to ensure that required image is in use and all extensions are enabled.
    - Confirm that the `blackfire` and `opentelemetry` extensions are not enabled simultaneously.

- Verify Install file:
    - Check that install file has required section to run `vendor/bin/console open-telemetry:generate` command.
 
- Verify Console and Monitoring dependency providers:
    - Make sure that `OpentelemetryGeneratorConsole` is wired as a console command.
    - Make sure that `OpentelemetryMonitoringExtensionPlugin` is wired as Monitoring plugin.

- Verify that all required packages are installed.