#!/usr/bin/env bash
#
# Generates an HTML documentation page from all WireMock mappings and loads it at GET /.
# Called by load-wiremock-mappings.sh — failures here are non-fatal to the load process.

set -e

MAPPINGS_DIR="${MAPPINGS_DIR:-./mappings}"

if [ -z "$WIREMOCK_URL" ]; then
  echo "Error: WIREMOCK_URL is not set"
  exit 1
fi

if [ ! -d "$MAPPINGS_DIR" ]; then
  echo "Mappings directory not found: $MAPPINGS_DIR"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed"
  exit 1
fi

DATA_FILE=$(mktemp)
SORTED_FILE=$(mktemp)
HTML_FILE=$(mktemp)
trap 'rm -f "$DATA_FILE" "$SORTED_FILE" "$HTML_FILE"' EXIT

html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# Collect endpoint data from each mapping file
for file in "$MAPPINGS_DIR"/*.json; do
  [ -f "$file" ] || continue
  filename=$(basename "$file" .json)

  case "$filename" in
    health*)             category="Health Checks" ;;
    fees-lookup*|fees-range*) category="Fees Register" ;;
    role-assignment*)    category="Role Assignment Service" ;;
    organisation*|civilDamages*|userOrganisation*) category="Reference Data — Organisations" ;;
    cmc-*)               category="CMC Claim Store" ;;
    bundle-*)            category="Bundle API" ;;
    send-letter*)        category="Send Letter" ;;
    noc-*)               category="Notice of Change" ;;
    lov-*)               category="Reference Data — Common Data" ;;
    location-ref-data*)  category="Location Reference Data" ;;
    cjes-*)              category="CJES" ;;
    docmosis*)           category="Docmosis" ;;
    sendgrid*)           category="SendGrid" ;;
    *)                   category="Other" ;;
  esac

  name=$(jq -r '.name // ""' "$file")
  method=$(jq -r '.request.method // "ANY"' "$file")
  url=$(jq -r '.request.url // .request.urlPath // .request.urlPattern // .request.urlPathPattern // "(unknown)"' "$file")
  url_type=$(jq -r 'if .request.urlPattern or .request.urlPathPattern then "regex" else "exact" end' "$file")
  status=$(jq -r '.response.status // 200' "$file")
  query_params=$(jq -r 'if .request.queryParameters then (.request.queryParameters | keys | join(", ")) else "" end' "$file")

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$category" "$name" "$method" "$url" "$url_type" "$status" "$query_params" \
    >> "$DATA_FILE"
done

sort "$DATA_FILE" > "$SORTED_FILE"
MAPPING_COUNT=$(wc -l < "$DATA_FILE" | tr -d ' ')
GENERATED_AT=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

# Build grouped HTML rows
BODY_HTML=""
CURRENT_CATEGORY=""
while IFS=$'\t' read -r category name method url url_type status query_params; do
  if [ "$category" != "$CURRENT_CATEGORY" ]; then
    [ -n "$CURRENT_CATEGORY" ] && BODY_HTML="${BODY_HTML}
        </tbody></table>
      </section>"
    BODY_HTML="${BODY_HTML}
      <section>
        <h2>$(html_escape "$category")</h2>
        <table>
          <thead>
            <tr><th>Method</th><th>URL / Pattern</th><th>Query Params</th><th>Status</th><th>Description</th></tr>
          </thead>
          <tbody>"
    CURRENT_CATEGORY="$category"
  fi

  case "$method" in
    GET)    badge="get" ;;
    POST)   badge="post" ;;
    PUT)    badge="put" ;;
    DELETE) badge="delete" ;;
    PATCH)  badge="patch" ;;
    *)      badge="other" ;;
  esac

  escaped_url=$(html_escape "$url")
  escaped_name=$(html_escape "$name")
  escaped_qp=$(html_escape "$query_params")

  if [ "$url_type" = "regex" ]; then
    url_cell="<code>${escaped_url}</code> <span class=\"tag\">regex</span>"
  else
    url_cell="<code>${escaped_url}</code>"
  fi

  [ -n "$escaped_qp" ] && qp_cell="<code>${escaped_qp}</code>" || qp_cell=""

  BODY_HTML="${BODY_HTML}
            <tr>
              <td><span class=\"badge ${badge}\">${method}</span></td>
              <td>${url_cell}</td>
              <td>${qp_cell}</td>
              <td><span class=\"status\">${status}</span></td>
              <td>${escaped_name}</td>
            </tr>"
done < "$SORTED_FILE"

[ -n "$CURRENT_CATEGORY" ] && BODY_HTML="${BODY_HTML}
        </tbody></table>
      </section>"

# Write static HTML header
cat > "$HTML_FILE" << 'STATIC_HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Civil WireMock — Endpoint Documentation</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f6fa; color: #2c3e50; }
    header { background: #1a2332; color: white; padding: 24px 40px; }
    header h1 { font-size: 22px; font-weight: 600; }
    header p { margin-top: 6px; color: #8fa3b3; font-size: 14px; }
    .meta { background: #263547; padding: 12px 40px; display: flex; gap: 32px; flex-wrap: wrap; }
    .meta span { color: #8fa3b3; font-size: 13px; }
    .meta strong { color: #e8ecf0; }
    .admin-links { background: #263547; padding: 0 40px 14px; display: flex; gap: 16px; }
    .admin-links a { color: #5b9dd9; font-size: 13px; text-decoration: none; }
    .admin-links a:hover { text-decoration: underline; }
    main { padding: 32px 40px; }
    section { background: white; border-radius: 8px; margin-bottom: 24px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); overflow: hidden; }
    section h2 { padding: 16px 20px; font-size: 15px; font-weight: 600; background: #f8f9fb; border-bottom: 1px solid #e8ecf0; color: #1a2332; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th { text-align: left; padding: 10px 16px; background: #f8f9fb; color: #6b7c93; font-weight: 500; border-bottom: 1px solid #e8ecf0; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }
    td { padding: 10px 16px; border-bottom: 1px solid #f0f3f6; vertical-align: middle; }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background: #fafbfc; }
    code { font-family: 'SFMono-Regular', Consolas, monospace; font-size: 12px; background: #f0f3f6; padding: 2px 6px; border-radius: 3px; word-break: break-all; }
    .badge { display: inline-block; padding: 3px 8px; border-radius: 4px; font-size: 11px; font-weight: 700; letter-spacing: 0.05em; font-family: monospace; }
    .badge.get    { background: #d4edda; color: #155724; }
    .badge.post   { background: #cce5ff; color: #004085; }
    .badge.put    { background: #fff3cd; color: #856404; }
    .badge.delete { background: #f8d7da; color: #721c24; }
    .badge.patch  { background: #e2d9f3; color: #4a235a; }
    .badge.other  { background: #e2e3e5; color: #383d41; }
    .tag { display: inline-block; padding: 1px 5px; border-radius: 3px; font-size: 10px; background: #fff3cd; color: #856404; margin-left: 4px; vertical-align: middle; }
    .status { font-family: monospace; font-size: 12px; font-weight: 600; color: #6b7c93; }
    footer { padding: 20px 40px; text-align: center; color: #8fa3b3; font-size: 12px; }
    footer a { color: #8fa3b3; }
  </style>
</head>
<body>
  <header>
    <h1>Civil WireMock — Endpoint Documentation</h1>
    <p>Shared stub mappings for Civil service preview &amp; test environments</p>
  </header>
STATIC_HEADER

# Append dynamic server info
printf '  <div class="meta">\n' >> "$HTML_FILE"
printf '    <span>Server: <strong>%s</strong></span>\n' "$WIREMOCK_URL" >> "$HTML_FILE"
printf '    <span>Mappings: <strong>%s</strong></span>\n' "$MAPPING_COUNT" >> "$HTML_FILE"
printf '    <span>Generated: <strong>%s</strong></span>\n' "$GENERATED_AT" >> "$HTML_FILE"
printf '  </div>\n' >> "$HTML_FILE"
printf '  <div class="admin-links">\n' >> "$HTML_FILE"
printf '    <a href="/__admin/mappings" target="_blank">/__admin/mappings</a>\n' >> "$HTML_FILE"
printf '    <a href="/__admin/requests" target="_blank">/__admin/requests</a>\n' >> "$HTML_FILE"
printf '  </div>\n' >> "$HTML_FILE"
printf '  <main>\n' >> "$HTML_FILE"

# Append generated table rows (use printf to avoid $ interpretation in regex patterns)
printf '%s\n' "$BODY_HTML" >> "$HTML_FILE"

# Append static footer
cat >> "$HTML_FILE" << 'STATIC_FOOTER'
  </main>
  <footer>
    Generated by <a href="https://github.com/hmcts/civil-wiremock-mappings">civil-wiremock-mappings</a>
    &middot; <a href="/__admin/mappings">Admin API</a>
  </footer>
</body>
</html>
STATIC_FOOTER

# Build and POST the WireMock mapping with the HTML inlined as body
MAPPING_JSON=$(jq -n --rawfile body "$HTML_FILE" '{
  "name": "Docs - Endpoint Documentation Page",
  "request": { "method": "GET", "url": "/" },
  "response": {
    "status": 200,
    "headers": { "Content-Type": "text/html; charset=utf-8" },
    "body": $body
  }
}')

RESPONSE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$WIREMOCK_URL/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d "$MAPPING_JSON")

if [ "$RESPONSE" = "201" ]; then
  echo "Documentation page loaded at $WIREMOCK_URL/"
else
  echo "Error: Failed to load documentation page (HTTP $RESPONSE)"
  exit 1
fi