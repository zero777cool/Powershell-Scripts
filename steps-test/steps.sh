# shellcheck shell=bash
# steps.sh — in-place step checklist for bash scripts
#
#   · pending   → running (blue)   ✓ done (green)   ✗ failed (red)   ↷ skipped (yellow)
#
# The list is drawn once and then updated in place; it never scrolls.
# Each step's own output goes to a log file, not the screen.
#
# USAGE
#   source "$(dirname "$0")/steps.sh"
#
#   function_steps_init "Server bootstrap" \
#       "Update package lists" \
#       "Install packages" \
#       "Harden sshd"
#
#   function_step_run 1 apt-get update
#   function_step_run 2 apt-get install -y tmux git
#   function_step_run 3 function_harden_sshd          # your own function works too
#   function_steps_finish
#
#   function_step_skip 3 "already hardened"           # mark a step skipped instead of running it
#
# RULES OF THE ROAD
#   * A step runs in a subshell with `set -Eeo pipefail`, so ANY failing command
#     inside it fails the step. To pass a value to later steps, call
#     `function_steps_set NAME "value"` inside the step; NAME is set in the main
#     script as soon as the step finishes.
#   * Steps get no keyboard input (stdin is /dev/null). Ask questions BEFORE
#     function_steps_init. If steps use sudo, run `sudo -v` before it too.
#   * On failure: the step turns red, the last $STEPS_TAIL log lines are shown,
#     and the script exits with the step's exit code (set STEPS_KEEP_GOING=1 to
#     carry on instead).
#   * With no terminal (cron, CI, piped, cloud-init) or a list taller than the
#     window, it prints one plain line per step change instead. STEPS_PLAIN=1 forces that.
#
# SETTINGS (set before sourcing or before function_steps_init)
#   STEPS_LOG         log file   (default: /tmp/<script>-<timestamp>.log)
#   STEPS_TAIL        log lines shown on failure (default 15)
#   STEPS_KEEP_GOING  1 = don't exit when a step fails
#   STEPS_PLAIN       1 = never redraw in place
#   STEPS_NO_CLEAR    1 = don't clear the screen at start (it's only ever cleared on a real terminal)
#   STEPS_NO_ICONS    1 = no emoji (title 🔧, done 🎉, failed 🚨, interrupted 🛑, log 📄)
#
# This file sets an EXIT/INT/TERM trap to restore the cursor. If your script
# needs its own EXIT trap, call function_steps__cleanup from it.

STEPS_NAMES=(); STEPS_STATE=(); STEPS_SECS=(); STEPS_NOTE=()
STEPS_COUNT=0; STEPS_FANCY=0; STEPS_COLOUR=0; STEPS_DRAWN=0
STEPS_CURRENT=0; STEPS_T0=0; STEPS_WIDTH=80
STEPS_VARS_FILE=""

# A few emoji for the title, summary and log lines (the step states keep → ✓ ✗ ↷ ·).
if [[ -z ${STEPS_NO_ICONS:-} ]]; then
  STEPS_I_TITLE='🔧 '; STEPS_I_DONE='🎉 '; STEPS_I_FAIL='🚨 '; STEPS_I_STOP='🛑 '; STEPS_I_LOG='📄 '
else
  STEPS_I_TITLE=''; STEPS_I_DONE='✓ '; STEPS_I_FAIL='✗ '; STEPS_I_STOP=''; STEPS_I_LOG=''
fi

# ── internals ────────────────────────────────────────────────────────────────

function_steps__fmt_secs() {
  local S=$1
  if (( S >= 3600 )); then printf '%dh %02dm' $((S/3600)) $((S%3600/60))
  elif (( S >= 60 )); then printf '%dm %02ds' $((S/60)) $((S%60))
  else printf '%ds' "$S"; fi
}

function_steps__c() {   # colour code, or nothing when colour is off
  if (( STEPS_COLOUR )); then printf '\033[%sm' "$1"; fi
}

function_steps__line() {   # print one step line (no newline)
  local I=$1 NAME=${STEPS_NAMES[$1]} STATE=${STEPS_STATE[$1]} TAIL="" MAX
  MAX=$(( STEPS_WIDTH - 22 )); (( MAX < 10 )) && MAX=10
  (( ${#NAME} > MAX )) && NAME="${NAME:0:MAX-1}…"
  case $STATE in
    done)    TAIL="  $(function_steps__c 2)$(function_steps__fmt_secs "${STEPS_SECS[$I]}")$(function_steps__c 0)"
             printf '%s✓%s %s%s' "$(function_steps__c '1;32')" "$(function_steps__c 0)" "$NAME" "$TAIL" ;;
    running) printf '%s→%s %s%s%s' "$(function_steps__c '1;34')" "$(function_steps__c 0)" "$(function_steps__c 1)" "$NAME" "$(function_steps__c 0)" ;;
    failed)  [[ -z ${STEPS_NOTE[$I]} ]] || TAIL="  $(function_steps__c 31)${STEPS_NOTE[$I]}$(function_steps__c 0)"
             printf '%s✗%s %s%s' "$(function_steps__c '1;31')" "$(function_steps__c 0)" "$NAME" "$TAIL" ;;
    skipped) [[ -z ${STEPS_NOTE[$I]} ]] || TAIL="  ${STEPS_NOTE[$I]}"
             printf '%s↷ %s%s%s' "$(function_steps__c 33)" "$NAME" "$TAIL" "$(function_steps__c 0)" ;;
    *)       printf '%s· %s%s' "$(function_steps__c 2)" "$NAME" "$(function_steps__c 0)" ;;
  esac
}

function_steps__draw() {   # fancy mode: redraw the whole list in place
  local I
  (( STEPS_DRAWN )) && printf '\033[%dA' "$STEPS_COUNT"
  for (( I = 1; I <= STEPS_COUNT; I++ )); do
    printf '\r\033[2K'; function_steps__line "$I"; printf '\n'
  done
  STEPS_DRAWN=1
}

function_steps__update() {   # called on every state change
  local I=$1
  if (( STEPS_FANCY )); then function_steps__draw
  else printf '[%d/%d] ' "$I" "$STEPS_COUNT"; function_steps__line "$I"; printf '\n'; fi
}

function_steps__cleanup() {
  (( STEPS_FANCY )) && printf '\033[?25h'   # show cursor
  [[ -n $STEPS_VARS_FILE ]] && rm -f "$STEPS_VARS_FILE"
  return 0
}

function_steps__interrupt() {
  if (( STEPS_CURRENT )) && [[ ${STEPS_STATE[$STEPS_CURRENT]} == running ]]; then
    STEPS_STATE[$STEPS_CURRENT]=failed; STEPS_NOTE[$STEPS_CURRENT]="interrupted"
    function_steps__update "$STEPS_CURRENT"
  fi
  function_steps__cleanup
  printf '\n%sInterrupted. %sLog: %s\n' "$STEPS_I_STOP" "$STEPS_I_LOG" "$STEPS_LOG"
  exit 130
}

# ── public API ───────────────────────────────────────────────────────────────

function_steps_init() {   # function_steps_init "Title" "Step 1" "Step 2" ...
  local TITLE=$1 ROWS; shift
  STEPS_NAMES=("" "$@"); STEPS_COUNT=$#
  STEPS_STATE=(""); STEPS_SECS=(""); STEPS_NOTE=("")
  local I; for (( I = 1; I <= STEPS_COUNT; I++ )); do STEPS_STATE[I]=pending; STEPS_SECS[I]=0; STEPS_NOTE[I]=""; done

  : "${STEPS_LOG:=${TMPDIR:-/tmp}/$(basename "${0%.*}")-$(date +%Y%m%d-%H%M%S).log}"
  : "${STEPS_TAIL:=15}"
  : > "$STEPS_LOG" || { echo "steps.sh: cannot write log $STEPS_LOG" >&2; return 1; }
  STEPS_VARS_FILE=$(mktemp "${TMPDIR:-/tmp}/steps-vars.XXXXXX")

  STEPS_COLOUR=0; STEPS_FANCY=0; STEPS_WIDTH=80
  if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
    STEPS_COLOUR=1
    STEPS_WIDTH=$(tput cols 2>/dev/null || echo 80)
    ROWS=$(tput lines 2>/dev/null || echo 24)
    if [[ -z ${STEPS_PLAIN:-} ]] && (( STEPS_COUNT + 4 <= ROWS )); then STEPS_FANCY=1; fi
  fi

  trap function_steps__cleanup EXIT
  trap function_steps__interrupt INT TERM

  STEPS_T0=$SECONDS
  if (( STEPS_COLOUR )) && [[ -z ${STEPS_NO_CLEAR:-} ]]; then printf '\033[H\033[2J'; fi   # clear screen (terminal only)
  printf '%s%s%s%s\n' "$(function_steps__c 1)" "$STEPS_I_TITLE" "$TITLE" "$(function_steps__c 0)"
  if (( STEPS_FANCY )); then
    printf '\033[?25l'   # hide cursor while redrawing
    function_steps__draw
  else
    printf 'Steps: %d · %slog: %s\n' "$STEPS_COUNT" "$STEPS_I_LOG" "$STEPS_LOG"
  fi
}

function_steps_set() {   # inside a step: function_steps_set NAME "value"
  printf '%s=%q\n' "$1" "$2" >> "$STEPS_VARS_FILE"
}

function_step_run() {   # function_step_run <n> command [args...]
  local I=$1 T0 RC LOG_START ERREXIT=0; shift
  STEPS_CURRENT=$I; STEPS_STATE[I]=running; function_steps__update "$I"
  printf '\n===== [%d/%d] %s  (%s)\n$ %s\n' "$I" "$STEPS_COUNT" "${STEPS_NAMES[$I]}" "$(date '+%F %T')" "$*" >> "$STEPS_LOG"

  LOG_START=$(( $(wc -l < "$STEPS_LOG") + 1 ))
  T0=$SECONDS
  # Turn off the caller's errexit around the subshell: a failing step must be
  # reported, not kill the script. (Running it as `cmd || RC=$?` would make bash
  # ignore the `set -e` inside the step, so we don't.)
  [[ $- == *e* ]] && ERREXIT=1 && set +e
  ( set -Eeo pipefail; "$@" ) >> "$STEPS_LOG" 2>&1 < /dev/null
  RC=$?
  (( ERREXIT )) && set -e
  STEPS_SECS[I]=$(( SECONDS - T0 ))
  # shellcheck disable=SC1090
  [[ -s $STEPS_VARS_FILE ]] && source "$STEPS_VARS_FILE"

  if (( RC == 0 )); then
    STEPS_STATE[I]="done"; function_steps__update "$I"
    STEPS_CURRENT=0; return 0
  fi

  STEPS_STATE[I]=failed; STEPS_NOTE[I]="exit $RC"; function_steps__update "$I"
  printf '\n%s%sStep %d failed: %s (exit %d). Its last output:%s\n' \
    "$(function_steps__c '1;31')" "$STEPS_I_FAIL" "$I" "${STEPS_NAMES[$I]}" "$RC" "$(function_steps__c 0)"
  tail -n "+$LOG_START" "$STEPS_LOG" | tail -n "$STEPS_TAIL" | sed 's/^/  /'
  printf '%sFull log: %s\n' "$STEPS_I_LOG" "$STEPS_LOG"
  printf '===== step failed with exit code %d\n' "$RC" >> "$STEPS_LOG"
  STEPS_CURRENT=0
  if [[ -n ${STEPS_KEEP_GOING:-} ]]; then
    # Reprint the list below so later steps redraw in the right place.
    (( STEPS_FANCY )) && { STEPS_DRAWN=0; printf '\n'; function_steps__draw; }
    return "$RC"
  fi
  exit "$RC"
}

function_step_skip() {   # function_step_skip <n> ["reason"]
  STEPS_STATE[$1]=skipped; STEPS_NOTE[$1]=${2:-}
  printf '\n===== [%d/%d] %s  skipped%s\n' "$1" "$STEPS_COUNT" "${STEPS_NAMES[$1]}" "${2:+: $2}" >> "$STEPS_LOG"
  function_steps__update "$1"
}

function_steps_finish() {   # print the summary line; returns 1 if any step failed
  local I FAILED=0 NOTRUN=0
  for (( I = 1; I <= STEPS_COUNT; I++ )); do
    case ${STEPS_STATE[$I]} in failed) FAILED=$((FAILED+1));; pending) NOTRUN=$((NOTRUN+1));; esac
  done
  function_steps__cleanup; STEPS_VARS_FILE=""
  local TOTAL EXTRA=""; TOTAL=$(function_steps__fmt_secs $(( SECONDS - STEPS_T0 )))
  (( NOTRUN )) && EXTRA=" ($NOTRUN not run)"
  printf '\n'
  if (( FAILED )); then
    printf '%s%s%d of %d steps failed%s in %s\n' "$(function_steps__c '1;31')" "$STEPS_I_FAIL" "$FAILED" "$STEPS_COUNT" "$(function_steps__c 0)" "$TOTAL"
    printf '%sLog: %s\n' "$STEPS_I_LOG" "$STEPS_LOG"
    return 1
  fi
  printf '%s%sDone%s · %d step(s) in %s%s\n' "$(function_steps__c '1;32')" "$STEPS_I_DONE" "$(function_steps__c 0)" "$STEPS_COUNT" "$TOTAL" "$EXTRA"
  printf '%sLog: %s\n' "$STEPS_I_LOG" "$STEPS_LOG"
}
