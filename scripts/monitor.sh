#!/usr/bin/env bash
set -euo pipefail

# monitor.sh -- Interactive live dashboard for parallel agent sessions.
#
# Navigate features with arrow keys or j/k, act on the selected feature
# with single-key commands. Auto-refreshes in the background.
#
# Usage:
#   ./scripts/monitor.sh            # interactive dashboard (default 5s refresh)
#   ./scripts/monitor.sh --watch    # same as above (kept for compat)
#   ./scripts/monitor.sh --watch 3  # custom refresh interval
#   ./scripts/monitor.sh --once     # print snapshot and exit (non-interactive)
#
# Navigation:
#   Up/k      Move selection up
#   Down/j    Move selection down
#   d         Feature details (JSON, commits, diff stats)
#   l         Recent commits on the feature branch
#   p         Open the feature's PR in browser
#   r         Reset feature to pending
#   c         Mark feature complete
#   x         Remove the feature's worktree
#   m         Merge the feature's PR
#   /         Refresh now
#   q         Quit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

INTERVAL=5
ONCE=false

case "${1:-}" in
    --once)    ONCE=true ;;
    --watch)
        if [ -n "${2:-}" ] && [ "$2" -gt 0 ] 2>/dev/null; then
            INTERVAL="$2"
        fi
        ;;
    --help|-h)
        sed -n '3,/^$/p' "$0" | sed 's/^# \?//'
        exit 0
        ;;
esac

# --- Colors ---
R='\033[0m'
DIM='\033[2m'
GRN='\033[32m'
YLW='\033[33m'
RED='\033[31m'
CYN='\033[36m'
BLD='\033[1m'
INV='\033[7m'

# --- State ---
SELECTED=0
FEATURE_IDS=()
FEATURE_COUNT=0
OVERLAY=""
CONFIRM_ACTION=""
CONFIRM_ID=""
STATUS_MSG=""

# --- Terminal setup ---
cleanup() {
    printf '\033[?25h'   # show cursor
    printf '\033[?1049l' # restore main screen
    stty "$ORIG_STTY" 2>/dev/null
}

if [ "$ONCE" = false ]; then
    ORIG_STTY=$(stty -g 2>/dev/null || echo "")
    trap cleanup EXIT INT TERM
    printf '\033[?1049h'  # alternate screen
    printf '\033[?25l'    # hide cursor
fi

# --- Helpers ---

feature_file() {
    local id="$1"
    echo "progress/${id}.json"
}

feature_field() {
    local file="$1" field="$2"
    jq -r ".${field} // empty" "$file" 2>/dev/null
}

worktree_for_branch() {
    local branch="$1"
    git worktree list --porcelain 2>/dev/null | awk -v b="$branch" '
        /^worktree / { wt=$2 }
        /^branch /   { if ($2 == "refs/heads/" b) print wt }
    '
}

pr_for_branch() {
    local branch="$1"
    if command -v gh &>/dev/null; then
        gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null || true
    fi
}

# --- Load features into arrays ---
load_features() {
    FEATURE_IDS=()
    shopt -s nullglob
    for f in progress/*.json; do
        [ -f "$f" ] || continue
        local id
        id=$(jq -r '.id // ""' "$f" 2>/dev/null)
        [ -n "$id" ] && FEATURE_IDS+=("$id")
    done
    FEATURE_COUNT=${#FEATURE_IDS[@]}
    if [ "$SELECTED" -ge "$FEATURE_COUNT" ] && [ "$FEATURE_COUNT" -gt 0 ]; then
        SELECTED=$((FEATURE_COUNT - 1))
    fi
}

# --- Render ---

render() {
    local lines=""

    # Header
    lines+="$(printf "${BLD}projd monitor${R}  ${DIM}%s${R}  ${DIM}refresh ${INTERVAL}s${R}" "$(date '+%H:%M:%S')")\n"
    lines+="\n"

    # Progress summary
    if [ "$FEATURE_COUNT" -gt 0 ]; then
        local done_n=0 wip_n=0 pending_n=0
        for id in "${FEATURE_IDS[@]}"; do
            local f="progress/${id}.json"
            local s
            s=$(jq -r '.status // "pending"' "$f" 2>/dev/null)
            case "$s" in
                complete)    done_n=$((done_n + 1)) ;;
                in_progress) wip_n=$((wip_n + 1)) ;;
                *)           pending_n=$((pending_n + 1)) ;;
            esac
        done

        local filled=$((done_n * 20 / FEATURE_COUNT))
        local empty=$((20 - filled))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done
        local pct=$((done_n * 100 / FEATURE_COUNT))

        lines+="$(printf "  ${GRN}%s${R}  ${BLD}%d%%%%${R}  ${GRN}%d${R} done  ${YLW}%d${R} wip  ${DIM}%d pending${R}  ${DIM}(%d total)${R}" "$bar" "$pct" "$done_n" "$wip_n" "$pending_n" "$FEATURE_COUNT")\n"
        lines+="\n"

        # Table header
        lines+="$(printf "  ${DIM}  %-20s  %-6s  %-25s  %s${R}" "FEATURE" "STATUS" "BRANCH" "INFO")\n"

        # Feature rows
        local idx=0
        for id in "${FEATURE_IDS[@]}"; do
            local f="progress/${id}.json"
            local status branch notes blocked_by icon info
            status=$(jq -r '.status // "pending"' "$f" 2>/dev/null)
            branch=$(jq -r '.branch // ""' "$f" 2>/dev/null)
            notes=$(jq -r '.notes // ""' "$f" 2>/dev/null)
            blocked_by=$(jq -r '.blocked_by // [] | join(", ")' "$f" 2>/dev/null)

            case "$status" in
                complete)    icon="${GRN}done ${R}" ;;
                in_progress) icon="${YLW}wip  ${R}" ;;
                *)
                    if [ -n "$blocked_by" ]; then
                        icon="${RED}block${R}"
                    else
                        icon="${DIM}pend ${R}"
                    fi
                    ;;
            esac

            local display_id="$id"
            [ ${#display_id} -gt 20 ] && display_id="${display_id:0:17}..."
            local display_branch="$branch"
            [ ${#display_branch} -gt 25 ] && display_branch="${display_branch:0:22}..."

            info=""
            if [ -n "$notes" ]; then
                info="$notes"
            elif [ -n "$blocked_by" ] && [ "$status" != "complete" ]; then
                info="blocked: $blocked_by"
            fi
            [ ${#info} -gt 35 ] && info="${info:0:32}..."

            local prefix="  "
            if [ "$idx" -eq "$SELECTED" ]; then
                lines+="$(printf "${INV}${BLD}> %-20s${R}  ${icon}  ${INV}%-25s${R}  ${DIM}%s${R}" "$display_id" "$display_branch" "$info")\n"
            else
                lines+="$(printf "  %-20s  ${icon}  %-25s  ${DIM}%s${R}" "$display_id" "$display_branch" "$info")\n"
            fi
            idx=$((idx + 1))
        done
    else
        lines+="$(printf "  ${DIM}No features in progress/${R}")\n"
    fi

    # Worktrees
    lines+="\n"
    local wt_lines
    wt_lines=$(git worktree list 2>/dev/null | tail -n +2 || true)
    if [ -n "$wt_lines" ]; then
        local wt_count
        wt_count=$(echo "$wt_lines" | wc -l | tr -d ' ')
        lines+="$(printf "  ${BLD}%d active worktree%s${R}" "$wt_count" "$([ "$wt_count" -ne 1 ] && echo 's' || echo '')")\n"
        while IFS= read -r line; do
            local wt_path wt_branch
            wt_path=$(echo "$line" | awk '{print $1}')
            wt_branch=$(echo "$line" | grep -o '\[.*\]' | tr -d '[]')
            lines+="$(printf "    ${CYN}%-25s${R}  ${DIM}%s${R}" "$wt_branch" "$wt_path")\n"
        done <<< "$wt_lines"
    else
        lines+="$(printf "  ${DIM}No active worktrees${R}")\n"
    fi

    # PRs
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        local prefix_val
        prefix_val=$(jq -r '.git.branch_prefix // "agent/"' agent.json 2>/dev/null)
        local prs
        prs=$(gh pr list --state open --json number,title,headRefName --jq ".[] | select(.headRefName | startswith(\"$prefix_val\"))" 2>/dev/null || true)
        if [ -n "$prs" ]; then
            local pr_count
            pr_count=$(echo "$prs" | jq -s 'length' 2>/dev/null || echo 0)
            lines+="\n"
            lines+="$(printf "  ${BLD}%d open PR%s${R}" "$pr_count" "$([ "$pr_count" -ne 1 ] && echo 's' || echo '')")\n"
            while IFS= read -r pr_line; do
                lines+="$(printf "  ${GRN}  %s${R}" "$pr_line")\n"
            done < <(echo "$prs" | jq -r '"#\(.number)  \(.title)"' 2>/dev/null)
        fi
    fi

    # Footer with key hints
    lines+="\n"
    if [ -n "$STATUS_MSG" ]; then
        lines+="$(printf "  ${GRN}%s${R}" "$STATUS_MSG")\n"
        lines+="\n"
    fi
    if [ -n "$CONFIRM_ACTION" ]; then
        lines+="$(printf "  ${YLW}%s '%s'? [y/N]${R}" "$CONFIRM_ACTION" "$CONFIRM_ID")\n"
    else
        lines+="$(printf "  ${DIM}j/k${R} navigate  ${DIM}d${R} detail  ${DIM}l${R} log  ${DIM}p${R} pr  ${DIM}r${R} reset  ${DIM}c${R} complete  ${DIM}x${R} kill  ${DIM}m${R} merge  ${DIM}q${R} quit")\n"
    fi

    # Write to screen
    printf '\033[2J\033[H'
    printf '%b' "$lines"
}

# --- Overlay display (pauses refresh, shows detail, waits for key) ---

show_overlay() {
    local content="$1"
    printf '\033[2J\033[H'
    printf '%b\n' "$content"
    printf '\n'
    printf "  ${DIM}Press any key to return...${R}"
    stty -echo -icanon min 1 time 0 2>/dev/null
    read -rsn1 _ 2>/dev/null || true
}

detail_overlay() {
    local id="$1"
    local f
    f=$(feature_file "$id")
    [ ! -f "$f" ] && return

    local out=""
    out+="$(printf "${BLD}Feature: %s${R}" "$id")\n"
    out+="$(printf "${DIM}%s${R}" "$(feature_field "$f" "name")")\n"
    out+="\n"

    # JSON
    out+="$(printf "${DIM}--- feature file ---${R}")\n"
    out+="$(jq '.' "$f" 2>/dev/null)\n"
    out+="\n"

    # Acceptance criteria
    local ac_count
    ac_count=$(jq '.acceptance_criteria | length' "$f" 2>/dev/null || echo 0)
    if [ "$ac_count" -gt 0 ]; then
        out+="$(printf "${BLD}Acceptance criteria:${R}")\n"
        while IFS= read -r line; do
            out+="  $line\n"
        done < <(jq -r '.acceptance_criteria[] // empty' "$f" 2>/dev/null | nl -ba -s '. ')
        out+="\n"
    fi

    # Branch log
    local branch
    branch=$(feature_field "$f" "branch")
    if [ -n "$branch" ] && git rev-parse --verify "$branch" &>/dev/null; then
        out+="$(printf "${BLD}Recent commits on ${CYN}%s${R}:" "$branch")\n"
        while IFS= read -r line; do
            out+="  $line\n"
        done < <(git log "$branch" --oneline -10 2>/dev/null)
        out+="\n"

        local base="main"
        git rev-parse --verify main &>/dev/null || base=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        out+="$(printf "${BLD}Diff vs %s:${R}" "$base")\n"
        while IFS= read -r line; do
            out+="  $line\n"
        done < <(git diff --stat "${base}...${branch}" 2>/dev/null)
        out+="\n"
    fi

    # Worktree
    if [ -n "$branch" ]; then
        local wt
        wt=$(worktree_for_branch "$branch")
        if [ -n "$wt" ]; then
            out+="$(printf "${BLD}Worktree:${R} ${DIM}%s${R}" "$wt")\n"
        fi
    fi

    # PR
    if [ -n "$branch" ] && command -v gh &>/dev/null; then
        local pr_num
        pr_num=$(pr_for_branch "$branch")
        if [ -n "$pr_num" ]; then
            out+="$(printf "${BLD}PR:${R} ${GRN}#%s${R}" "$pr_num")\n"
            out+="$(gh pr view "$pr_num" --json title,state,additions,deletions,reviewDecision,url \
                --jq '"  \(.url)\n  +\(.additions) -\(.deletions)  \(.state)  review: \(.reviewDecision // "none")"' 2>/dev/null || true)\n"
        fi
    fi

    show_overlay "$out"
}

log_overlay() {
    local id="$1"
    local f
    f=$(feature_file "$id")
    [ ! -f "$f" ] && return

    local branch
    branch=$(feature_field "$f" "branch")
    if [ -z "$branch" ] || ! git rev-parse --verify "$branch" &>/dev/null; then
        show_overlay "$(printf "${DIM}No branch for %s${R}" "$id")"
        return
    fi

    local out=""
    out+="$(printf "${BLD}Commits on ${CYN}%s${R}:" "$branch")\n\n"
    while IFS= read -r line; do
        out+="  $line\n"
    done < <(git log "$branch" --oneline -25 2>/dev/null)

    show_overlay "$out"
}

# --- Actions ---

selected_id() {
    if [ "$FEATURE_COUNT" -gt 0 ] && [ "$SELECTED" -lt "$FEATURE_COUNT" ]; then
        echo "${FEATURE_IDS[$SELECTED]}"
    fi
}

action_reset() {
    local id="$1"
    local f
    f=$(feature_file "$id")
    [ ! -f "$f" ] && return

    local branch
    branch=$(feature_field "$f" "branch")
    if [ -n "$branch" ]; then
        local wt
        wt=$(worktree_for_branch "$branch")
        if [ -n "$wt" ]; then
            git worktree remove --force "$wt" 2>/dev/null || true
        fi
    fi

    local tmp
    tmp=$(mktemp)
    jq '.status = "pending" | .branch = "" | .notes = ""' "$f" > "$tmp" && mv "$tmp" "$f"
    STATUS_MSG="Reset '$id' to pending"
}

action_complete() {
    local id="$1"
    local f
    f=$(feature_file "$id")
    [ ! -f "$f" ] && return

    local tmp
    tmp=$(mktemp)
    jq '.status = "complete"' "$f" > "$tmp" && mv "$tmp" "$f"
    STATUS_MSG="Marked '$id' complete"
}

action_kill() {
    local id="$1"
    local f
    f=$(feature_file "$id")
    [ ! -f "$f" ] && return

    local branch
    branch=$(feature_field "$f" "branch")
    [ -z "$branch" ] && { STATUS_MSG="No branch for '$id'"; return; }

    local wt
    wt=$(worktree_for_branch "$branch")
    [ -z "$wt" ] && { STATUS_MSG="No worktree for '$id'"; return; }

    git worktree remove --force "$wt" 2>/dev/null && \
        STATUS_MSG="Removed worktree for '$id'" || \
        STATUS_MSG="Failed to remove worktree"
}

action_pr_open() {
    local id="$1"
    local f
    f=$(feature_file "$id")
    [ ! -f "$f" ] && return

    local branch
    branch=$(feature_field "$f" "branch")
    [ -z "$branch" ] && { STATUS_MSG="No branch for '$id'"; return; }

    command -v gh &>/dev/null || { STATUS_MSG="gh CLI not available"; return; }

    local pr_num
    pr_num=$(pr_for_branch "$branch")
    [ -z "$pr_num" ] && { STATUS_MSG="No open PR for '$id'"; return; }

    gh pr view "$pr_num" --web 2>/dev/null
    STATUS_MSG="Opened PR #${pr_num}"
}

action_merge() {
    local id="$1"
    local f
    f=$(feature_file "$id")
    [ ! -f "$f" ] && return

    local branch
    branch=$(feature_field "$f" "branch")
    [ -z "$branch" ] && { STATUS_MSG="No branch for '$id'"; return; }

    command -v gh &>/dev/null || { STATUS_MSG="gh CLI not available"; return; }

    local pr_num
    pr_num=$(pr_for_branch "$branch")
    [ -z "$pr_num" ] && { STATUS_MSG="No open PR for '$id'"; return; }

    if gh pr merge "$pr_num" --merge 2>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq '.status = "complete"' "$f" > "$tmp" && mv "$tmp" "$f"
        STATUS_MSG="Merged PR #${pr_num}, marked '$id' complete"
    else
        STATUS_MSG="Failed to merge PR #${pr_num}"
    fi
}

# --- Non-interactive mode ---

if [ "$ONCE" = true ]; then
    load_features
    # Simple non-interactive output (no alternate screen, no key reading)
    SELECTED=-1  # no selection highlight

    printf "${BLD}projd monitor${R}  ${DIM}%s${R}\n\n" "$(date '+%H:%M:%S')"

    if [ "$FEATURE_COUNT" -gt 0 ]; then
        local done_n=0 wip_n=0 pending_n=0
        for id in "${FEATURE_IDS[@]}"; do
            local s
            s=$(jq -r '.status // "pending"' "progress/${id}.json" 2>/dev/null)
            case "$s" in
                complete)    done_n=$((done_n + 1)) ;;
                in_progress) wip_n=$((wip_n + 1)) ;;
                *)           pending_n=$((pending_n + 1)) ;;
            esac
        done

        local filled=$((done_n * 20 / FEATURE_COUNT))
        local empty_b=$((20 - filled))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty_b; i++)); do bar+="░"; done
        local pct=$((done_n * 100 / FEATURE_COUNT))
        printf "  ${GRN}%s${R}  ${BLD}%d%%%%${R}  ${GRN}%d${R} done  ${YLW}%d${R} wip  ${DIM}%d pending${R}  ${DIM}(%d total)${R}\n\n" \
            "$bar" "$pct" "$done_n" "$wip_n" "$pending_n" "$FEATURE_COUNT"

        printf "  ${DIM}%-20s  %-6s  %-25s  %s${R}\n" "FEATURE" "STATUS" "BRANCH" "INFO"
        for id in "${FEATURE_IDS[@]}"; do
            local f="progress/${id}.json"
            local status branch icon
            status=$(jq -r '.status // "pending"' "$f" 2>/dev/null)
            branch=$(jq -r '.branch // ""' "$f" 2>/dev/null)
            case "$status" in
                complete)    icon="done " ;;
                in_progress) icon="wip  " ;;
                *)           icon="pend " ;;
            esac
            printf "  %-20s  %-6s  %s\n" "$id" "$icon" "$branch"
        done
    else
        printf "  ${DIM}No features in progress/${R}\n"
    fi
    echo ""
    exit 0
fi

# --- Main loop ---

stty -echo -icanon min 0 time 0 2>/dev/null

load_features
render

LAST_REFRESH=$(date +%s)

while true; do
    # Read a key (non-blocking)
    KEY=""
    read -rsn1 -t 0.1 KEY 2>/dev/null || true

    # Handle escape sequences (arrow keys)
    if [ "$KEY" = $'\033' ]; then
        read -rsn1 -t 0.05 SEQ1 2>/dev/null || true
        read -rsn1 -t 0.05 SEQ2 2>/dev/null || true
        if [ "$SEQ1" = "[" ]; then
            case "$SEQ2" in
                A) KEY="UP" ;;
                B) KEY="DOWN" ;;
                *) KEY="" ;;
            esac
        fi
    fi

    NEEDS_RENDER=false

    # Handle confirmation mode
    if [ -n "$CONFIRM_ACTION" ]; then
        case "$KEY" in
            y|Y)
                case "$CONFIRM_ACTION" in
                    "Reset")    action_reset "$CONFIRM_ID" ;;
                    "Complete") action_complete "$CONFIRM_ID" ;;
                    "Kill worktree for") action_kill "$CONFIRM_ID" ;;
                    "Merge PR for")     action_merge "$CONFIRM_ID" ;;
                esac
                CONFIRM_ACTION=""
                CONFIRM_ID=""
                load_features
                NEEDS_RENDER=true
                ;;
            n|N|"")
                if [ -n "$KEY" ]; then
                    CONFIRM_ACTION=""
                    CONFIRM_ID=""
                    STATUS_MSG="Cancelled"
                    NEEDS_RENDER=true
                fi
                ;;
            *)
                CONFIRM_ACTION=""
                CONFIRM_ID=""
                STATUS_MSG="Cancelled"
                NEEDS_RENDER=true
                ;;
        esac
    elif [ -n "$KEY" ]; then
        STATUS_MSG=""
        local id
        id=$(selected_id)

        case "$KEY" in
            q) break ;;
            k|UP)
                if [ "$SELECTED" -gt 0 ]; then
                    SELECTED=$((SELECTED - 1))
                    NEEDS_RENDER=true
                fi
                ;;
            j|DOWN)
                if [ "$SELECTED" -lt $((FEATURE_COUNT - 1)) ]; then
                    SELECTED=$((SELECTED + 1))
                    NEEDS_RENDER=true
                fi
                ;;
            d)
                [ -n "$id" ] && detail_overlay "$id"
                NEEDS_RENDER=true
                ;;
            l)
                [ -n "$id" ] && log_overlay "$id"
                NEEDS_RENDER=true
                ;;
            p)
                [ -n "$id" ] && action_pr_open "$id"
                NEEDS_RENDER=true
                ;;
            r)
                if [ -n "$id" ]; then
                    CONFIRM_ACTION="Reset"
                    CONFIRM_ID="$id"
                    NEEDS_RENDER=true
                fi
                ;;
            c)
                if [ -n "$id" ]; then
                    CONFIRM_ACTION="Complete"
                    CONFIRM_ID="$id"
                    NEEDS_RENDER=true
                fi
                ;;
            x)
                if [ -n "$id" ]; then
                    CONFIRM_ACTION="Kill worktree for"
                    CONFIRM_ID="$id"
                    NEEDS_RENDER=true
                fi
                ;;
            m)
                if [ -n "$id" ]; then
                    CONFIRM_ACTION="Merge PR for"
                    CONFIRM_ID="$id"
                    NEEDS_RENDER=true
                fi
                ;;
            /)
                load_features
                NEEDS_RENDER=true
                ;;
        esac
    fi

    # Auto-refresh on interval
    NOW=$(date +%s)
    if [ $((NOW - LAST_REFRESH)) -ge "$INTERVAL" ]; then
        load_features
        LAST_REFRESH=$NOW
        NEEDS_RENDER=true
    fi

    if [ "$NEEDS_RENDER" = true ]; then
        render
    fi
done
