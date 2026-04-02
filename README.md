# Civil WireMock Mappings

Shared WireMock stub mappings used across Civil repositories for preview and testing environments.

## Structure

```
mappings/           - Root-level WireMock mapping JSON files (loaded by default)
mappings/cui/       - Citizen UI specific mappings (loaded with --include cui)
__files/            - Response body files referenced by mappings via bodyFileName
__files/cui/        - Response body files for CUI mappings
bin/                - Scripts for loading mappings into a running WireMock instance
```

## Usage

### Loading mappings into a WireMock instance

Set the `WIREMOCK_URL` environment variable and run the load script:

```bash
export WIREMOCK_URL="https://wiremock-civil-service-pr-123.preview.platform.hmcts.net"
./bin/load-wiremock-mappings.sh
```

By default, only root-level mappings are loaded. To include additional subdirectories (e.g., CUI mappings):

```bash
# Load root + CUI mappings
./bin/load-wiremock-mappings.sh --include cui

# Load multiple subdirectories
./bin/load-wiremock-mappings.sh --include "cui,other"

# Using environment variable
INCLUDE_DIRS="cui" ./bin/load-wiremock-mappings.sh
```

The script will:
1. Wait for WireMock to be ready
2. Clear all existing mappings
3. Load mappings from `mappings/` (root-level only by default)
4. Load mappings from specified subdirectories when `--include` is used
5. Inline any `bodyFileName` references from `__files/`

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

| Variable         | Required | Default | Description                                          |
|------------------|----------|---------|------------------------------------------------------|
| `WIREMOCK_URL`   | Yes      | -       | Base URL of the WireMock instance                    |
| `INCLUDE_DIRS`   | No       | -       | Comma-separated subdirectories to include (e.g., `cui`) |
| `MAX_RETRIES`    | No       | 30      | Max readiness check attempts                         |
| `RETRY_INTERVAL` | No       | 10      | Seconds between readiness check attempts             |

### Command-line options

| Option           | Description                                                    |
|------------------|----------------------------------------------------------------|
| `--include <dirs>` | Comma-separated subdirectories to include (overrides `INCLUDE_DIRS`) |
| `--help`, `-h`   | Show usage information                                         |
