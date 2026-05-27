#!/usr/bin/env bash
# Converts CHANGELOG.md to HTML and injects into site/index.html
# Replaces the <!-- CHANGELOG_CONTENT --> placeholder.
# Run from repo root.
set -euo pipefail

CHANGELOG="CHANGELOG.md"
INDEX="site/index.html"

if [ ! -f "$CHANGELOG" ]; then
  echo "Warning: $CHANGELOG not found, skipping changelog injection"
  exit 0
fi

# Parse CHANGELOG.md into HTML entries
# Skips the title line and [Unreleased] section
html=""
in_unreleased=false
current_version=""
current_date=""
current_category=""
in_list=false

while IFS= read -r line; do
  # Skip the main title
  if [[ "$line" =~ ^#\ Changelog ]]; then
    continue
  fi

  # Skip description lines
  if [[ "$line" =~ ^All\ notable|^Format\ follows ]]; then
    continue
  fi

  # Version header: ## [5.0.1] - 2026-03-21  or  ## [Unreleased]
  if [[ "$line" =~ ^##\ \[([^\]]+)\](\ -\ (.+))? ]]; then
    version="${BASH_REMATCH[1]}"
    date="${BASH_REMATCH[3]:-}"

    # Close previous entry
    if [ "$in_list" = true ]; then
      html+="</ul>"
      in_list=false
    fi
    if [ -n "$current_version" ] && [ "$current_version" != "Unreleased" ]; then
      html+="</div>"
    fi

    current_version="$version"
    current_date="$date"
    current_category=""

    if [ "$version" = "Unreleased" ]; then
      in_unreleased=true
      continue
    fi

    in_unreleased=false
    tag="v${version}"
    html+="<div class=\"changelog-entry\">"
    html+="<div class=\"changelog-version\"><a href=\"https://github.com/haad/Clipsmith/releases/tag/${tag}\">${version}</a></div>"
    if [ -n "$date" ]; then
      html+="<div class=\"changelog-date\">${date}</div>"
    fi
    continue
  fi

  # Skip unreleased content
  if [ "$in_unreleased" = true ]; then
    continue
  fi

  # Skip if no version yet
  if [ -z "$current_version" ] || [ "$current_version" = "Unreleased" ]; then
    continue
  fi

  # Category header: ### Added, ### Fixed, etc.
  if [[ "$line" =~ ^###\ (.+) ]]; then
    category="${BASH_REMATCH[1]}"
    if [ "$in_list" = true ]; then
      html+="</ul>"
      in_list=false
    fi
    html+="<div class=\"changelog-category\">${category}</div>"
    html+="<ul class=\"changelog-list\">"
    in_list=true
    continue
  fi

  # List item: - Some change
  if [[ "$line" =~ ^-\ (.+) ]]; then
    item="${BASH_REMATCH[1]}"
    # Convert **bold** to <strong>
    item=$(echo "$item" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g')
    # Convert `code` to <code>
    item=$(echo "$item" | sed 's/`\([^`]*\)`/<code style="font-size:0.75rem;background:var(--bg-page);padding:1px 4px;border-radius:3px;border:1px solid var(--border-color);">\1<\/code>/g')
    html+="<li>${item}</li>"
    continue
  fi

done < "$CHANGELOG"

# Close last entry
if [ "$in_list" = true ]; then
  html+="</ul>"
fi
if [ -n "$current_version" ] && [ "$current_version" != "Unreleased" ]; then
  html+="</div>"
fi

# Inject into index.html (replace placeholder)
if grep -q '<!-- CHANGELOG_CONTENT -->' "$INDEX"; then
  # Use a temp file for safe replacement (sed with multiline HTML is fragile)
  python3 -c "
import sys
with open('$INDEX', 'r') as f:
    content = f.read()
replacement = sys.stdin.read()
content = content.replace('<!-- CHANGELOG_CONTENT -->', replacement)
with open('$INDEX', 'w') as f:
    f.write(content)
" <<< "$html"
  echo "Changelog injected into $INDEX"
else
  echo "Warning: <!-- CHANGELOG_CONTENT --> placeholder not found in $INDEX"
fi
