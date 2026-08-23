#!/bin/bash
# Claude Code statusLine.
# Layout:  model(effort) | branch | ctx <bar> N% | 5h N%  7d N%
#
# Data comes from the JSON piped on stdin. Every segment degrades gracefully:
#   - effort: .effort.level, else the `effort` in ~/.claude/settings.json
#   - context %: .context_window.used_percentage, else computed from the
#                transcript's last assistant usage / context_window_size
#   - 5h / 7d: .rate_limits.{five_hour,seven_day}.used_percentage (only present
#              for Pro/Max after the first API response) — shown as "-" if absent

input=$(cat)

# ---- helpers ---------------------------------------------------------------
# ANSI: 32=green 33=yellow 31=red 36=cyan 35=magenta ; 2=dim ; 0=reset
RESET=$'\033[0m'; DIM=$'\033[2m'
SEP=" ${DIM}|${RESET} "

# color by utilization: <50 green, <80 yellow, else red
pct_color() {
  local p=$1
  if   [ "$p" -ge 80 ]; then printf '\033[1;31m'
  elif [ "$p" -ge 50 ]; then printf '\033[1;33m'
  else printf '\033[1;32m'
  fi
}

# 10-wide progress bar for an integer percentage
make_bar() {
  local pct=$1 width=10 i filled empty b=""
  filled=$(( (pct * width + 50) / 100 ))
  (( filled > width )) && filled=$width
  (( filled < 0 ))     && filled=0
  empty=$(( width - filled ))
  for ((i=0; i<filled; i++)); do b+="█"; done
  for ((i=0; i<empty;  i++)); do b+="░"; done
  printf '%s' "$b"
}

# round a possibly-float value to an int; empty/null -> empty
to_int() {
  local v="$1"
  [ -z "$v" ] || [ "$v" = "null" ] && return 0
  printf '%.0f' "$v" 2>/dev/null
}

# ---- extract fields --------------------------------------------------------
model=$(echo "$input"  | jq -r '.model.display_name // .model.id // "?"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
if [ -z "$effort" ]; then
  for f in "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.local.json" \
           "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json" \
           "$HOME/.claude/settings.json"; do
    effort=$(jq -r '.effortLevel // .effort // empty' "$f" 2>/dev/null)
    [ -n "$effort" ] && break
  done
fi

cwd=$(echo "$input"        | jq -r '.workspace.current_dir // .cwd // "."')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# context window %
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
if [ -z "$ctx_pct" ] || [ "$ctx_pct" = "null" ]; then
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    used=$(grep '"type":"assistant"' "$transcript" 2>/dev/null | tail -1 \
      | jq -r '(.message.usage.input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)' 2>/dev/null)
    if [ -n "$used" ] && [ "$used" != "null" ]; then
      ctx_pct=$(awk -v u="$used" -v s="$ctx_size" 'BEGIN{ if(s>0) printf "%.0f", u*100/s; else print 0 }')
    fi
  fi
fi
ctx_pct=$(to_int "$ctx_pct"); [ -z "$ctx_pct" ] && ctx_pct=0

# rate-limit windows (may be absent)
h5=$(to_int "$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')")
d7=$(to_int "$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')")

# git branch (+ dirty flag)
branch=""; dirty=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ] && dirty="✗"
fi

# ---- assemble --------------------------------------------------------------
out=""

# model(effort)
if [ -n "$effort" ]; then
  out+=$(printf '\033[1;36m%s\033[0;36m(%s)%s' "$model" "$effort" "$RESET")
else
  out+=$(printf '\033[1;36m%s%s' "$model" "$RESET")
fi

# branch
if [ -n "$branch" ]; then
  out+="$SEP"
  out+=$(printf '\033[0;35m%s%s' "$branch" "$RESET")
  [ -n "$dirty" ] && out+=$(printf ' \033[1;31m%s%s' "$dirty" "$RESET")
fi

# context bar
cc=$(pct_color "$ctx_pct")
out+="$SEP"
out+=$(printf '%sctx%s %s%s%s %s%d%%%s' \
  "$DIM" "$RESET" "$cc" "$(make_bar "$ctx_pct")" "$RESET" "$cc" "$ctx_pct" "$RESET")

# 5h / 7d windows
out+="$SEP"
if [ -n "$h5" ]; then
  out+=$(printf '%s5h%s %s%d%%%s' "$DIM" "$RESET" "$(pct_color "$h5")" "$h5" "$RESET")
else
  out+=$(printf '%s5h%s %s-%s' "$DIM" "$RESET" "$DIM" "$RESET")
fi
out+="  "
if [ -n "$d7" ]; then
  out+=$(printf '%s7d%s %s%d%%%s' "$DIM" "$RESET" "$(pct_color "$d7")" "$d7" "$RESET")
else
  out+=$(printf '%s7d%s %s-%s' "$DIM" "$RESET" "$DIM" "$RESET")
fi

printf '%s' "$out"
