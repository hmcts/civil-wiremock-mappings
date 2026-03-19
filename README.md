# Civil WireMock Mappings

Shared WireMock stub mappings used across Civil repositories for preview and testing environments.

## Structure

```
mappings/    - WireMock mapping JSON files (request/response stubs)
__files/     - Response body files referenced by mappings via bodyFileName
bin/         - Scripts for loading mappings into a running WireMock instance
```

## Usage

### Loading mappings into a WireMock instance

Set the `WIREMOCK_URL` environment variable and run the load script:

```bash
export WIREMOCK_URL="https://wiremock-civil-service-pr-123.preview.platform.hmcts.net"
./bin/load-wiremock-mappings.sh
```

The script will:
1. Wait for WireMock to be ready
2. Clear all existing mappings
3. Load each mapping from `mappings/`, inlining any `bodyFileName` references from `__files/`

### Pulling mappings into a consuming repo

Add a pull script to your repo (see example in `civil-service`):

```bash
#!/usr/bin/env bash

branchName=${1:-main}

git clone https://github.com/hmcts/civil-wiremock-mappings.git
cd civil-wiremock-mappings
echo "Switch to ${branchName} branch on civil-wiremock-mappings"
git checkout ${branchName}
cd ..

cp -r ./civil-wiremock-mappings/mappings .
cp -r ./civil-wiremock-mappings/__files .
cp -r ./civil-wiremock-mappings/bin/. ./bin/
rm -rf ./civil-wiremock-mappings
```

Then call the pull script followed by the load script in your Jenkinsfile:

```groovy
./bin/pull-latest-wiremock-mappings.sh main
./bin/load-wiremock-mappings.sh
```

## Configuration

The load script supports these environment variables:

| Variable         | Required | Default | Description                              |
|------------------|----------|---------|------------------------------------------|
| `WIREMOCK_URL`   | Yes      | -       | Base URL of the WireMock instance        |
| `MAX_RETRIES`    | No       | 30      | Max readiness check attempts             |
| `RETRY_INTERVAL` | No       | 10      | Seconds between readiness check attempts |
