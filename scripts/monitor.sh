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
if [ "$ONCE" = false ]; then
    ORIG_STTY=$(stty -g 2>/dev/null || echo "sane")

    cleanup() {
        stty "$ORIG_STTY" 2>/dev/null
        printf '\033[?25h'   # show cursor
        printf '\033[?1049l' # restore main screen
    }

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

# Resolve the branch for a feature: check feature file, then try prefix+id.
resolve_branch() {
    local id="$1"
    local f
    f=$(feature_file "$id")
    local branch=""
    [ -f "$f" ] && branch=$(feature_field "$f" "branch")
    if [ -z "$branch" ]; then
        # Try to infer from agent.json prefix
        local prefix
        prefix=$(jq -r '.git.branch_prefix // "agent/"' agent.json 2>/dev/null)
        local candidate="${prefix}${id}"
        if git rev-parse --verify "$candidate" &>/dev/null; then
            branch="$candidate"
        fi
    fi
    echo "$branch"
}

pr_for_branch() {
    local branch="$1"
    if command -v gh &>/dev/null; then
        gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null || true
    fi
}

# --- Cached data arrays (populated by load_features / load_slow_data) ---
# Feature data -- parallel arrays indexed by position
F_STATUS=()    # "pending" | "in_progress" | "complete"
F_BRANCH=()
F_NOTES=()
F_BLOCKED=()

# Slow data -- refreshed on interval only
CACHED_WT=""       # pre-formatted worktree lines
CACHED_WT_COUNT=0
CACHED_PR=""       # pre-formatted PR lines
CACHED_PR_COUNT=0

# Agent activity -- parallel array indexed same as FEATURE_IDS
F_AGENT=()   # populated by load_slow_data

# --- Load features into arrays (sorted: wip, ready, blocked, complete) ---
# Reads each JSON file once with a single jq call per file.
load_features() {
    local wip_ids=() ready_ids=() block_ids=() done_ids=()
    local wip_s=()   ready_s=()   block_s=()   done_s=()
    local wip_br=()  ready_br=()  block_br=()  done_br=()
    local wip_no=()  ready_no=()  block_no=()  done_no=()
    local wip_bl=()  ready_bl=()  block_bl=()  done_bl=()

    shopt -s nullglob
    for f in progress/*.json; do
        [ -f "$f" ] || continue
        # Single jq call: emit tab-separated fields
        local row
        row=$(jq -r '[
            (.id // ""),
            (.status // "pending"),
            (.branch // ""),
            (.notes // ""),
            ((.blocked_by // []) | join(", "))
        ] | @tsv' "$f" 2>/dev/null) || continue

        IFS=$'\t' read -r _id _st _br _no _bl <<< "$row"
        [ -z "$_id" ] && continue

        case "$_st" in
            in_progress)
                wip_ids+=("$_id"); wip_s+=("$_st"); wip_br+=("$_br"); wip_no+=("$_no"); wip_bl+=("$_bl") ;;
            complete)
                done_ids+=("$_id"); done_s+=("$_st"); done_br+=("$_br"); done_no+=("$_no"); done_bl+=("$_bl") ;;
            *)
                if [ -n "$_bl" ]; then
                    block_ids+=("$_id"); block_s+=("$_st"); block_br+=("$_br"); block_no+=("$_no"); block_bl+=("$_bl")
                else
                    ready_ids+=("$_id"); ready_s+=("$_st"); ready_br+=("$_br"); ready_no+=("$_no"); ready_bl+=("$_bl")
                fi
                ;;
        esac
    done

    # Cross-reference active worktrees: if a worktree branch matches
    # {prefix}{feature-id}, that feature is in-progress even if the main
    # repo's progress file hasn't been updated yet (the agent writes to
    # its worktree copy, not the main repo).
    local prefix
    prefix=$(jq -r '.git.branch_prefix // "agent/"' agent.json 2>/dev/null)
    local wt_branches=""
    wt_branches=$(git worktree list --porcelain 2>/dev/null | awk '/^branch / { sub("refs/heads/", "", $2); print $2 }')

    # Build lookup of active worktree branches
    local _all_ids=("${wip_ids[@]+"${wip_ids[@]}"}" "${ready_ids[@]+"${ready_ids[@]}"}" "${block_ids[@]+"${block_ids[@]}"}" "${done_ids[@]+"${done_ids[@]}"}")

    if [ -n "$wt_branches" ]; then
        while IFS= read -r wt_br; do
            [ -z "$wt_br" ] && continue
            # Extract feature id from branch: strip prefix
            local fid="${wt_br#"$prefix"}"
            [ "$fid" = "$wt_br" ] && continue  # didn't match prefix

            # Find this feature in the non-wip buckets and move it to wip
            local found=false
            for ((i=0; i<${#ready_ids[@]}; i++)); do
                if [ "${ready_ids[$i]}" = "$fid" ]; then
                    wip_ids+=("$fid"); wip_s+=("in_progress"); wip_br+=("$wt_br"); wip_no+=("${ready_no[$i]}"); wip_bl+=("${ready_bl[$i]}")
                    unset 'ready_ids[i]' 'ready_s[i]' 'ready_br[i]' 'ready_no[i]' 'ready_bl[i]'
                    ready_ids=("${ready_ids[@]+"${ready_ids[@]}"}"); ready_s=("${ready_s[@]+"${ready_s[@]}"}"); ready_br=("${ready_br[@]+"${ready_br[@]}"}"); ready_no=("${ready_no[@]+"${ready_no[@]}"}"); ready_bl=("${ready_bl[@]+"${ready_bl[@]}"}")
                    found=true; break
                fi
            done
            if [ "$found" = false ]; then
                for ((i=0; i<${#block_ids[@]}; i++)); do
                    if [ "${block_ids[$i]}" = "$fid" ]; then
                        wip_ids+=("$fid"); wip_s+=("in_progress"); wip_br+=("$wt_br"); wip_no+=("${block_no[$i]}"); wip_bl+=("${block_bl[$i]}")
                        unset 'block_ids[i]' 'block_s[i]' 'block_br[i]' 'block_no[i]' 'block_bl[i]'
                        block_ids=("${block_ids[@]+"${block_ids[@]}"}"); block_s=("${block_s[@]+"${block_s[@]}"}"); block_br=("${block_br[@]+"${block_br[@]}"}"); block_no=("${block_no[@]+"${block_no[@]}"}"); block_bl=("${block_bl[@]+"${block_bl[@]}"}")
                        found=true; break
                    fi
                done
            fi
            # Also patch existing wip entries that have no branch
            if [ "$found" = false ]; then
                for ((i=0; i<${#wip_ids[@]}; i++)); do
                    if [ "${wip_ids[$i]}" = "$fid" ] && [ -z "${wip_br[$i]}" ]; then
                        wip_br[$i]="$wt_br"
                        break
                    fi
                done
            fi
        done <<< "$wt_branches"
    fi

    FEATURE_IDS=("${wip_ids[@]+"${wip_ids[@]}"}" "${ready_ids[@]+"${ready_ids[@]}"}" "${block_ids[@]+"${block_ids[@]}"}" "${done_ids[@]+"${done_ids[@]}"}")
    F_STATUS=("${wip_s[@]+"${wip_s[@]}"}" "${ready_s[@]+"${ready_s[@]}"}" "${block_s[@]+"${block_s[@]}"}" "${done_s[@]+"${done_s[@]}"}")
    F_BRANCH=("${wip_br[@]+"${wip_br[@]}"}" "${ready_br[@]+"${ready_br[@]}"}" "${block_br[@]+"${block_br[@]}"}" "${done_br[@]+"${done_br[@]}"}")
    F_NOTES=("${wip_no[@]+"${wip_no[@]}"}" "${ready_no[@]+"${ready_no[@]}"}" "${block_no[@]+"${block_no[@]}"}" "${done_no[@]+"${done_no[@]}"}")
    F_BLOCKED=("${wip_bl[@]+"${wip_bl[@]}"}" "${ready_bl[@]+"${ready_bl[@]}"}" "${block_bl[@]+"${block_bl[@]}"}" "${done_bl[@]+"${done_bl[@]}"}")

    FEATURE_COUNT=${#FEATURE_IDS[@]}
    if [ "$SELECTED" -ge "$FEATURE_COUNT" ] && [ "$FEATURE_COUNT" -gt 0 ]; then
        SELECTED=$((FEATURE_COUNT - 1))
    fi
}

# --- Load slow data (worktrees, PRs) -- called on timed refresh only ---
load_slow_data() {
    # Worktrees
    CACHED_WT=""
    CACHED_WT_COUNT=0
    local wt_raw
    wt_raw=$(git worktree list 2>/dev/null | tail -n +2 || true)
    if [ -n "$wt_raw" ]; then
        CACHED_WT_COUNT=$(echo "$wt_raw" | wc -l | tr -d ' ')
        CACHED_WT=""
        while IFS= read -r line; do
            local wt_path wt_branch
            wt_path=$(echo "$line" | awk '{print $1}')
            wt_branch=$(echo "$line" | grep -o '\[.*\]' | tr -d '[]')
            CACHED_WT+="$(printf "    ${CYN}%-25s${R}  ${DIM}%s${R}" "$wt_branch" "$wt_path")\n"
        done <<< "$wt_raw"
    fi

    # Agent activity for in-progress features (parallel array)
    F_AGENT=()
    for ((i=0; i<FEATURE_COUNT; i++)); do
        local _st="${F_STATUS[$i]}"
        local _br="${F_BRANCH[$i]}"

        if [ "$_st" != "in_progress" ] || [ -z "$_br" ]; then
            F_AGENT+=("")
            continue
        fi

        local info_parts=""

        # Worktree path for this branch
        local _wt
        _wt=$(worktree_for_branch "$_br")
        if [ -n "$_wt" ]; then
            info_parts+="worktree active"
        fi

        # Commit count and last commit message on this branch (vs main)
        if git rev-parse --verify "$_br" &>/dev/null; then
            local base="main"
            git rev-parse --verify main &>/dev/null || base=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
            local commits
            commits=$(git rev-list --count "${base}..${_br}" 2>/dev/null || echo 0)
            if [ "$commits" -gt 0 ]; then
                local last_msg
                last_msg=$(git log "$_br" -1 --format='%s' 2>/dev/null)
                [ ${#last_msg} -gt 40 ] && last_msg="${last_msg:0:37}..."
                local diff_stat
                diff_stat=$(git diff --shortstat "${base}...${_br}" 2>/dev/null | sed 's/ file.*/f/' | sed 's/.*changed, *//' | sed 's/ insertion.*/+/' | sed 's/ deletion.*/-/' | tr -d '\n' | tr ',' ' ')
                [ -n "$info_parts" ] && info_parts+="  "
                info_parts+="${commits} commits"
                [ -n "$diff_stat" ] && info_parts+="  ${diff_stat}"
                info_parts+="  last: ${last_msg}"
            fi
        fi

        F_AGENT+=("$info_parts")
    done

    # PRs (skip if gh not available)
    CACHED_PR=""
    CACHED_PR_COUNT=0
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        local prefix_val
        prefix_val=$(jq -r '.git.branch_prefix // "agent/"' agent.json 2>/dev/null)
        local prs
        prs=$(gh pr list --state open --json number,title,headRefName --jq ".[] | select(.headRefName | startswith(\"$prefix_val\"))" 2>/dev/null || true)
        if [ -n "$prs" ]; then
            CACHED_PR_COUNT=$(echo "$prs" | jq -s 'length' 2>/dev/null || echo 0)
            CACHED_PR=""
            while IFS= read -r pr_line; do
                CACHED_PR+="$(printf "  ${GRN}  %s${R}" "$pr_line")\n"
            done < <(echo "$prs" | jq -r '"#\(.number)  \(.title)"' 2>/dev/null)
        fi
    fi
}

# --- Render (pure output from cached data -- no external calls) ---

render() {
    local lines=""

    # Header
    lines+="$(printf "${BLD}projd monitor${R}  ${DIM}%s${R}  ${DIM}refresh ${INTERVAL}s${R}" "$(date '+%H:%M:%S')")\n"
    lines+="\n"

    # Progress summary
    if [ "$FEATURE_COUNT" -gt 0 ]; then
        local done_n=0 wip_n=0 pending_n=0
        for ((i=0; i<FEATURE_COUNT; i++)); do
            case "${F_STATUS[$i]}" in
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

        lines+="$(printf "  ${GRN}%s${R}  ${BLD}%d%%${R}  ${GRN}%d${R} done  ${YLW}%d${R} wip  ${DIM}%d pending${R}  ${DIM}(%d total)${R}" "$bar" "$pct" "$done_n" "$wip_n" "$pending_n" "$FEATURE_COUNT")\n"
        lines+="\n"

        # Table header
        lines+="$(printf "  ${DIM}  %-22s %-5s %s${R}" "FEATURE" "STATE" "DETAILS")\n"

        # Feature rows from cached arrays
        for ((idx=0; idx<FEATURE_COUNT; idx++)); do
            local id="${FEATURE_IDS[$idx]}"
            local status="${F_STATUS[$idx]}"
            local branch="${F_BRANCH[$idx]}"
            local notes="${F_NOTES[$idx]}"
            local blocked_by="${F_BLOCKED[$idx]}"
            local icon detail

            case "$status" in
                complete)    icon="${GRN}done ${R}" ;;
                in_progress) icon="${YLW}wip  ${R}" ;;
                *)
                    if [ -n "$blocked_by" ]; then
                        icon="${RED}block${R}"
                    else
                        icon="${DIM}ready${R}"
                    fi
                    ;;
            esac

            # Combine branch, agent info, blocked_by, and notes into one detail string
            detail=""
            if [ -n "$branch" ]; then
                detail="${CYN}${branch}${R}"
                # Show agent activity for in-progress features
                local agent_detail="${F_AGENT[$idx]:-}"
                if [ -n "$agent_detail" ]; then
                    detail+="  ${DIM}${agent_detail}${R}"
                elif [ -n "$notes" ]; then
                    detail+="  ${DIM}${notes}${R}"
                fi
            elif [ -n "$blocked_by" ] && [ "$status" != "complete" ]; then
                detail="${DIM}needs: ${blocked_by}${R}"
            elif [ -n "$notes" ]; then
                detail="${DIM}${notes}${R}"
            fi

            local display_id="$id"
            [ ${#display_id} -gt 22 ] && display_id="${display_id:0:19}..."

            if [ "$idx" -eq "$SELECTED" ]; then
                lines+="$(printf "${INV}${BLD}> %-22s${R} ${icon} %b" "$display_id" "$detail")\n"
            else
                lines+="$(printf "  %-22s ${icon} %b" "$display_id" "$detail")\n"
            fi
        done
    else
        lines+="$(printf "  ${DIM}No features in progress/${R}")\n"
    fi

    # Worktrees (from cache)
    lines+="\n"
    if [ "$CACHED_WT_COUNT" -gt 0 ]; then
        lines+="$(printf "  ${BLD}%d active worktree%s${R}" "$CACHED_WT_COUNT" "$([ "$CACHED_WT_COUNT" -ne 1 ] && echo 's' || echo '')")\n"
        lines+="$CACHED_WT"
    else
        lines+="$(printf "  ${DIM}No active worktrees${R}")\n"
    fi

    # PRs (from cache)
    if [ "$CACHED_PR_COUNT" -gt 0 ]; then
        lines+="\n"
        lines+="$(printf "  ${BLD}%d open PR%s${R}" "$CACHED_PR_COUNT" "$([ "$CACHED_PR_COUNT" -ne 1 ] && echo 's' || echo '')")\n"
        lines+="$CACHED_PR"
    fi

    # Footer
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
    branch=$(resolve_branch "$id")
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
    branch=$(resolve_branch "$id")
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
    branch=$(resolve_branch "$id")
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
    branch=$(resolve_branch "$id")
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
    branch=$(resolve_branch "$id")
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
    branch=$(resolve_branch "$id")
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
        done_n=0; wip_n=0; pending_n=0
        for id in "${FEATURE_IDS[@]}"; do
            s=$(jq -r '.status // "pending"' "progress/${id}.json" 2>/dev/null)
            case "$s" in
                complete)    done_n=$((done_n + 1)) ;;
                in_progress) wip_n=$((wip_n + 1)) ;;
                *)           pending_n=$((pending_n + 1)) ;;
            esac
        done

        filled=$((done_n * 20 / FEATURE_COUNT))
        empty_b=$((20 - filled))
        bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty_b; i++)); do bar+="░"; done
        pct=$((done_n * 100 / FEATURE_COUNT))
        printf "  ${GRN}%s${R}  ${BLD}%d%%${R}  ${GRN}%d${R} done  ${YLW}%d${R} wip  ${DIM}%d pending${R}  ${DIM}(%d total)${R}\n\n" \
            "$bar" "$pct" "$done_n" "$wip_n" "$pending_n" "$FEATURE_COUNT"

        printf "  ${DIM}%-20s  %-6s  %-25s  %s${R}\n" "FEATURE" "STATUS" "BRANCH" "INFO"
        for id in "${FEATURE_IDS[@]}"; do
            f="progress/${id}.json"
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

# Disable echo so keypresses don't litter the screen.
# Use bash read -t for timeouts (portable, no stty timing conflicts).
stty -echo 2>/dev/null

load_features
load_slow_data
render

LAST_REFRESH=$(date +%s)

while true; do
    # Read one byte with 1-second timeout. Keypresses return immediately;
    # timeout returns empty (exit code > 128) and drives the auto-refresh.
    KEY=""
    IFS= read -rsn1 -t 1 KEY 2>/dev/null || true

    # Arrow keys send 3 bytes: ESC [ A/B. Read the remaining bytes.
    # Use -t 1 (not -t 0 which fails on bash 3.2). The bytes are already
    # buffered so read returns instantly despite the 1s timeout.
    if [[ "$KEY" == $'\033' ]]; then
        SEQ1="" SEQ2=""
        IFS= read -rsn1 -t 1 SEQ1 2>/dev/null || true
        IFS= read -rsn1 -t 1 SEQ2 2>/dev/null || true
        if [[ "$SEQ1" == "[" ]]; then
            case "$SEQ2" in
                A) KEY="UP" ;;
                B) KEY="DOWN" ;;
                *) KEY="" ;;
            esac
        else
            KEY=""
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
        load_slow_data
        LAST_REFRESH=$NOW
        NEEDS_RENDER=true
    fi

    if [ "$NEEDS_RENDER" = true ]; then
        render
    fi
done
