# opentelemetry-installer

This is a simple script to integrate OpenTelemetry in the project. The script `otel_integrator.sh` should be copied to the root of the project.
First param is a project namespace. Default to `Pyz`.
Second param is deploy file name. Default to `deploy.yml`
Third param is install script name. Default to `config/install/docker.yml`

## Prerequisites
Tool `yq` should be installed in the system. E.g. via brew `brew install yq`

## Review
After the script is done, review your changes. Make sure that deploy file is updated and run `docker/sdk boot {%YOUR_FILE_NAME%}`. Make sure that `blackfire` extension and `opentelemetry` extension are not enabled in the same time.