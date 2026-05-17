#!/usr/bin/env bash
# Tests/run_fixtures.sh
#
# Generates Cherri code for each fixture in fixtures.json by calling the
# local Ollama API directly, then checks must_contain / must_not_contain.
#
# Usage:
#   chmod +x Tests/run_fixtures.sh
#   ./Tests/run_fixtures.sh                    # uses default model
#   ./Tests/run_fixtures.sh qwen3.5:9b         # specify model
#   ./Tests/run_fixtures.sh qwen2.5-coder:7b   # test a weaker model

set -euo pipefail

MODEL="${1:-qwen2.5-coder:7b}"
FIXTURES="$(dirname "$0")/fixtures.json"
OLLAMA_URL="http://localhost:11434/api/chat"
CHERRI="${CHERRI_PATH:-/opt/homebrew/bin/cherri}"

# Load the system prompt from the resource file
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUIDE_PATH="$SCRIPT_DIR/../AgenticShortcuts/Resources/CherriLLMGuide.txt"
if [[ ! -f "$GUIDE_PATH" ]]; then
    echo "ERROR: CherriLLMGuide.txt not found at $GUIDE_PATH"
    exit 1
fi
SYSTEM_PROMPT="$(cat "$GUIDE_PATH")"

PASS=0
FAIL=0
ERRORS=()

count=$(jq 'length' "$FIXTURES")
echo "Running $count fixtures with model: $MODEL"
echo "────────────────────────────────────────"

for i in $(seq 0 $((count - 1))); do
    id=$(jq -r ".[$i].id" "$FIXTURES")
    prompt=$(jq -r ".[$i].prompt" "$FIXTURES")
    notes=$(jq -r ".[$i].notes // empty" "$FIXTURES")

    printf "%-40s " "$id"

    # Call Ollama
    user_msg="Create a Cherri shortcut that does the following:\n\n$prompt\n\nOutput ONLY raw Cherri source code. No markdown, no commentary."
    payload=$(jq -n \
        --arg model "$MODEL" \
        --arg system "$SYSTEM_PROMPT" \
        --arg user "$user_msg" \
        '{model: $model, messages: [{role:"system",content:$system},{role:"user",content:$user}], stream: false}')

    response=$(curl -s -X POST "$OLLAMA_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 120)

    code=$(echo "$response" | jq -r '.message.content // empty' 2>/dev/null)

    # Strip markdown fences if present
    if echo "$code" | grep -q '```'; then
        code=$(echo "$code" | sed '/^```/d')
    fi

    if [[ -z "$code" ]]; then
        echo "FAIL (no code returned)"
        FAIL=$((FAIL + 1))
        ERRORS+=("$id: LLM returned no code")
        continue
    fi

    # Write to temp file and compile
    tmp=$(mktemp /tmp/fixture_XXXXXX.cherri)
    echo "$code" > "$tmp"

    compile_ok=true
    compile_err=""
    if ! compile_err=$("$CHERRI" "$tmp" --skip-sign 2>&1); then
        compile_ok=false
    fi
    rm -f "$tmp" "${tmp%.cherri}.shortcut" "${tmp%.cherri}_unsigned.shortcut" 2>/dev/null || true

    # Check must_contain
    check_fail=false
    fail_reasons=()

    must_contains=$(jq -r ".[$i].must_contain[]" "$FIXTURES" 2>/dev/null)
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        if ! echo "$code" | grep -qF "$token"; then
            fail_reasons+=("missing: '$token'")
            check_fail=true
        fi
    done <<< "$must_contains"

    must_nots=$(jq -r ".[$i].must_not_contain[]" "$FIXTURES" 2>/dev/null)
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        if echo "$code" | grep -qF "$token"; then
            fail_reasons+=("found forbidden: '$token'")
            check_fail=true
        fi
    done <<< "$must_nots"

    if ! $compile_ok; then
        fail_reasons+=("compile error: $(echo "$compile_err" | head -1)")
        check_fail=true
    fi

    if $check_fail; then
        echo "FAIL"
        for r in "${fail_reasons[@]}"; do
            echo "       → $r"
        done
        FAIL=$((FAIL + 1))
        ERRORS+=("$id")
    else
        echo "PASS"
        PASS=$((PASS + 1))
    fi
done

echo "────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed  (model: $MODEL)"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failed fixtures:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    exit 1
fi
