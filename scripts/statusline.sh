#!/usr/bin/env bash
# Claude Code status line: model | context usage | rolling token totals
#
# Token totals are a heuristic indicator of how close you are to your Pro
# subscription limits. Anthropic doesn't publish the exact limit numbers and
# doesn't expose a "% of limit used" via any API, so this just sums tokens
# from the local transcripts under ~/.claude/projects/ over the last 5 hours
# (matches the rolling session window) and last 7 days (matches the weekly
# window). Run /usage occasionally to see what these totals correspond to in
# percentage terms on your plan.

input=$(cat)

CYAN=$'\033[36m'
GREEN=$'\033[32m'
ORANGE=$'\033[38;5;208m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

model=$(echo "$input" | jq -r '.model.display_name // "Unknown model"')

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ]; then
  pct_int=$(printf "%.0f" "$used_pct")
  if [ "$pct_int" -lt 80 ]; then
    ctx_color=$GREEN
    battery="🔋"
  elif [ "$pct_int" -lt 99 ]; then
    ctx_color=$ORANGE
    battery="🪫"
  else
    ctx_color=$RED
    battery="🪫"
  fi
  context_str="${ctx_color}${battery} ${pct_int}%${RESET}"
else
  context_str="🔋 -"
fi

projects_dir="${HOME}/.claude/projects"
now=$(date -u +%s)
cutoff_7d=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)

read -r sum_5h sum_7d < <(
  find "$projects_dir" -name "*.jsonl" -newermt "$cutoff_7d" -print0 2>/dev/null \
    | xargs -0 -r cat 2>/dev/null \
    | jq -r --argjson now "$now" '
        select(.message.usage)
        | (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) as $ts
        | ($now - $ts) as $age
        | ((.message.usage.input_tokens // 0)
           + (.message.usage.output_tokens // 0)
           + (.message.usage.cache_creation_input_tokens // 0)
           + (.message.usage.cache_read_input_tokens // 0)) as $tok
        | [$age, $tok] | @tsv
      ' \
    | awk 'BEGIN { s5=0; s7=0 }
           $1 < 18000  { s5 += $2 }
           $1 < 604800 { s7 += $2 }
           END { printf "%d %d\n", s5, s7 }'
)
sum_5h=${sum_5h:-0}
sum_7d=${sum_7d:-0}

human() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n/1000000
    else if (n >= 1000) printf "%.0fk", n/1000
    else printf "%d", n
  }'
}

h_5h=$(human "$sum_5h")
h_7d=$(human "$sum_7d")

printf "${CYAN}⚡ %s${RESET} | %s | ${YELLOW}5h:%s${RESET} | ${YELLOW}7d:%s${RESET}" \
  "$model" "$context_str" "$h_5h" "$h_7d"
