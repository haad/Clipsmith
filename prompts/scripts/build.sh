#!/bin/bash
# scripts/build.sh — Compile prompts/*.md files into prompts.json
# Zero dependencies: bash 3.2+, jq, sed, awk, grep (all pre-installed on macOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROMPTS_DIR="$REPO_ROOT/prompts"
OUTPUT="$REPO_ROOT/prompts.json"
CATALOG="$REPO_ROOT/catalog.yaml"

# Verify prerequisites
if ! command -v jq > /dev/null 2>&1; then
    echo "ERROR: jq is required but not installed. Run: brew install jq" >&2
    exit 1
fi

if [ ! -f "$CATALOG" ]; then
    echo "ERROR: catalog.yaml not found at $CATALOG" >&2
    exit 1
fi

# Read catalog metadata
CATALOG_VERSION=$(grep '^version:' "$CATALOG" | awk '{print $2}')
VALID_CATEGORIES=$(grep '^ *- ' "$CATALOG" | sed 's/^ *- //')

if [ -z "$CATALOG_VERSION" ]; then
    echo "ERROR: Could not read version from $CATALOG" >&2
    exit 1
fi

# Pass 1: Collect all IDs, detect duplicates (POSIX string accumulation — bash 3.2 safe)
ALL_IDS=""
for file in $(find "$PROMPTS_DIR" -name '*.md' -type f | sort); do
    id=$(basename "$file" .md)
    ALL_IDS="${ALL_IDS}${id}
"
done

DUPS=$(printf '%s' "$ALL_IDS" | sort | uniq -d)
if [ -n "$DUPS" ]; then
    echo "ERROR: Duplicate prompt IDs detected: $(printf '%s' "$DUPS" | tr '\n' ' ')" >&2
    exit 1
fi

# Pass 2: Parse each file and build JSON objects
declare -a PROMPT_JSONS=()   # indexed array — bash 3.2 safe (only associative arrays require bash 4+)

for file in $(find "$PROMPTS_DIR" -name '*.md' -type f | sort); do
    id=$(basename "$file" .md)
    dir_category=$(basename "$(dirname "$file")")

    # Extract frontmatter block (lines between first and second ---)
    frontmatter=$(awk '/^---$/{count++; if(count==1){next}; if(count==2){exit}} count==1{print}' "$file")

    # Parse required fields
    # Title: strip key prefix, then strip surrounding quotes if present.
    # sed 's/^title:[[:space:]]*//' handles "title: foo" and 'title: "foo: bar"'.
    # The second sed strips one layer of surrounding double-quotes, preserving any
    # colons or other characters inside the value (CONTEXT.md locked: colon-in-title support).
    title=$(printf '%s\n' "$frontmatter" | grep '^title:' | sed 's/^title:[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/' || true)
    version=$(printf '%s\n' "$frontmatter" | grep '^version:' | awk '{print $2}' || true)

    # Parse optional category override (|| true: prevent set -e exit when field absent)
    fm_category=$(printf '%s\n' "$frontmatter" | grep '^category:' | sed 's/^category:[[:space:]]*//' | sed 's/^"\(.*\)"$/\1/' || true)

    # Resolve category: frontmatter override takes precedence over directory name
    category="${fm_category:-$dir_category}"

    # Validate required fields — name the offending file in error messages
    if [ -z "$title" ]; then
        echo "ERROR: Missing required field 'title' in $file" >&2
        exit 1
    fi
    if [ -z "$version" ]; then
        echo "ERROR: Missing required field 'version' in $file" >&2
        exit 1
    fi
    if ! printf '%s\n' "$VALID_CATEGORIES" | grep -qx "$category"; then
        echo "ERROR: Invalid category '$category' in $file (valid: $(printf '%s\n' "$VALID_CATEGORIES" | tr '\n' ' '))" >&2
        exit 1
    fi

    # Extract body (everything after second ---) and strip leading blank lines (BILD-11)
    body=$(awk 'BEGIN{n=0} /^---$/{n++; if(n==2){found=1; next}} found{print}' "$file" \
          | sed '/./,$!d')

    # JSON-encode body safely — handles newlines, quotes, backslashes (BILD-09)
    # printf '%s' (no \n) prevents jq -Rs capturing a spurious trailing newline
    content_json=$(printf '%s' "$body" | jq -Rs '.')

    # Build prompt JSON object with exactly 5 fields — no extras (JSON-02)
    prompt_json=$(jq -n \
        --arg     id       "$id" \
        --arg     title    "$title" \
        --arg     category "$category" \
        --argjson version  "$version" \
        --argjson content  "$content_json" \
        '{id: $id, title: $title, category: $category, version: $version, content: $content}')

    PROMPT_JSONS+=("$prompt_json")
done

if [ "${#PROMPT_JSONS[@]}" -eq 0 ]; then
    echo "ERROR: No .md files found under $PROMPTS_DIR" >&2
    exit 1
fi

# Assemble final JSON — prompts already sorted alphabetically by id (find | sort above)
printf '%s\n' "${PROMPT_JSONS[@]}" \
    | jq -s --argjson v "$CATALOG_VERSION" '{version: $v, prompts: .}' > "$OUTPUT"

COUNT=$(jq '.prompts | length' "$OUTPUT")
echo "Built $OUTPUT: $COUNT prompt(s), catalog version $CATALOG_VERSION"

# Structural validation — verify assembled prompts.json has the expected shape
if ! jq -e '
  (.version | type == "number" and . > 0) and
  (.prompts | type == "array" and length > 0) and
  (.prompts | all(has("id") and has("title") and has("category") and has("version") and has("content"))) and
  (.prompts | all(.id != "" and .title != "" and .content != ""))
' "$OUTPUT" > /dev/null; then
    echo "ERROR: prompts.json failed structural validation" >&2
    exit 1
fi
echo "Validation passed: prompts.json structure is valid"
