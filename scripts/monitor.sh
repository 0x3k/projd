#!/usr/bin/env bash
set -euo pipefail

# monitor.sh -- Live progress monitor for parallel agent sessions.
#
# Shows feature status, active worktrees/agents, and PR state.
# Run from another terminal while /projd-hands-off is dispatching.
#
# Usage:
#   ./scripts/monitor.sh            # interactive dashboard
#   ./scripts/monitor.sh --watch    # auto-refresh every 5 seconds
#   ./scripts/monitor.sh --watch 3  # auto-refresh every 3 seconds
#
# Interactive commands:
#   d  <feature>    Show feature details (JSON, branch log, diff stats)
#   pr <feature>    Open the feature's PR in the browser
#   log <feature>   Show recent commits on the feature's branch
#   reset <feature> Reset feature to pending (clear branch and status)
#   done <feature>  Mark feature as complete
#   kill <feature>  Remove the feature's worktree
#   merge <feature> Merge the feature's PR via gh
#   r               Refresh the display
#   q               Quit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

WATCH=false
INTERVAL=5

if [ "${1:-}" = "--watch" ]; then
    WATCH=true
    if [ -n "${2:-}" ] && [ "$2" -gt 0 ] 2>/dev/null; then
        INTERVAL="$2"
    fi
fi

# --- Colors ---
R='\033[0m'
DIM='\033[2m'
GRN='\033[32m'
YLW='\033[33m'
RED='\033[31m'
CYN='\033[36m'
BLD='\033[1m'

# --- Helpers ---

# Get the feature JSON file path for an id.
feature_file() {
    local id="$1"
    local f="progress/${id}.json"
    if [ -f "$f" ]; then
        echo "$f"
        return 0
    fi
    # Try partial match
    for candidate in progress/*.json; do
        [ -f "$candidate" ] || continue
        local cid
        cid=$(jq -r '.id // ""' "$candidate" 2>/dev/null)
        if [[ "$cid" == *"$id"* ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# Get a field from a feature file.
feature_field() {
    local file="$1" field="$2"
    jq -r ".${field} // empty" "$file" 2>/dev/null
}

# Find the worktree path for a branch.
worktree_for_branch() {
    local branch="$1"
    git worktree list --porcelain 2>/dev/null | awk -v b="$branch" '
        /^worktree / { wt=$2 }
        /^branch /   { if ($2 == "refs/heads/" b) print wt }
    '
}

# Find the PR number for a branch.
pr_for_branch() {
    local branch="$1"
    if command -v gh &>/dev/null; then
        gh pr list --head "$branch" --state open --json number --jq '.[0].number' 2>/dev/null || true
    fi
}

print_status() {
    if [ "$WATCH" = true ]; then
        printf '\033[2J\033[H'
    fi

    echo -e "${BLD}projd monitor${R}  ${DIM}$(date '+%H:%M:%S')${R}"
    echo ""

    # --- Features ---
    if [ -d progress ] && compgen -G "progress/*.json" >/dev/null 2>&1; then
        done_n=0; wip_n=0; pending_n=0; total=0

        for f in progress/*.json; do
            [ -f "$f" ] || continue
            total=$((total + 1))
            s=$(jq -r '.status // "pending"' "$f" 2>/dev/null)
            case "$s" in
                complete)    done_n=$((done_n + 1)) ;;
                in_progress) wip_n=$((wip_n + 1)) ;;
                *)           pending_n=$((pending_n + 1)) ;;
            esac
        done

        # Progress bar
        if [ "$total" -gt 0 ]; then
            filled=$((done_n * 20 / total))
            empty=$((20 - filled))
            bar=""
            for ((i=0; i<filled; i++)); do bar+="█"; done
            for ((i=0; i<empty; i++)); do bar+="░"; done
            pct=$((done_n * 100 / total))
            echo -e "  ${GRN}${bar}${R}  ${BLD}${pct}%%${R}  ${GRN}${done_n}${R} done  ${YLW}${wip_n}${R} wip  ${DIM}${pending_n} pending${R}  ${DIM}(${total} total)${R}"
        fi
        echo ""

        # Per-feature table
        printf "  ${DIM}%-20s  %-12s  %-25s  %s${R}\n" "FEATURE" "STATUS" "BRANCH" "NOTES"
        printf "  ${DIM}%-20s  %-12s  %-25s  %s${R}\n" "-------" "------" "------" "-----"

        for f in progress/*.json; do
            [ -f "$f" ] || continue
            id=$(jq -r '.id // "?"' "$f" 2>/dev/null)
            status=$(jq -r '.status // "pending"' "$f" 2>/dev/null)
            branch=$(jq -r '.branch // ""' "$f" 2>/dev/null)
            notes=$(jq -r '.notes // ""' "$f" 2>/dev/null)
            blocked_by=$(jq -r '.blocked_by // [] | join(", ")' "$f" 2>/dev/null)

            case "$status" in
                complete)    icon="${GRN}done${R}" ;;
                in_progress) icon="${YLW}wip ${R}" ;;
                *)
                    if [ -n "$blocked_by" ]; then
                        icon="${RED}block${R}"
                    else
                        icon="${DIM}pend${R}"
                    fi
                    ;;
            esac

            [ ${#id} -gt 20 ] && id="${id:0:17}..."
            [ ${#branch} -gt 25 ] && branch="${branch:0:22}..."
            note_text=""
            if [ -n "$notes" ]; then
                note_text="$notes"
                [ ${#note_text} -gt 40 ] && note_text="${note_text:0:37}..."
            elif [ -n "$blocked_by" ] && [ "$status" != "complete" ]; then
                note_text="blocked by: $blocked_by"
            fi

            printf "  %-20s  ${icon}%-6s  %-25s  ${DIM}%s${R}\n" "$id" "" "$branch" "$note_text"
        done
    else
        echo -e "  ${DIM}No features in progress/${R}"
    fi

    # --- Worktrees ---
    echo ""
    wt_lines=$(git worktree list 2>/dev/null | tail -n +2 || true)
    if [ -n "$wt_lines" ]; then
        wt_count=$(echo "$wt_lines" | wc -l | tr -d ' ')
        echo -e "  ${BLD}${wt_count} active worktree$([ "$wt_count" -ne 1 ] && echo 's' || echo '')${R}"
        echo "$wt_lines" | while IFS= read -r line; do
            wt_path=$(echo "$line" | awk '{print $1}')
            wt_branch=$(echo "$line" | grep -o '\[.*\]' | tr -d '[]')
            echo -e "    ${CYN}${wt_branch}${R}  ${DIM}${wt_path}${R}"
        done
    else
        echo -e "  ${DIM}No active worktrees${R}"
    fi

    # --- PRs ---
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        prefix=$(jq -r '.git.branch_prefix // "agent/"' agent.json 2>/dev/null)
        prs=$(gh pr list --state open --json number,title,headRefName,url --jq ".[] | select(.headRefName | startswith(\"$prefix\"))" 2>/dev/null || true)
        if [ -n "$prs" ]; then
            echo ""
            pr_count=$(echo "$prs" | jq -s 'length' 2>/dev/null || echo 0)
            echo -e "  ${BLD}${pr_count} open PR$([ "$pr_count" -ne 1 ] && echo 's' || echo '')${R}"
            echo "$prs" | jq -r '"    #\(.number)  \(.title)  \(.url)"' 2>/dev/null | while IFS= read -r line; do
                echo -e "  ${GRN}${line}${R}"
            done
        fi
    fi

    echo ""
}

# --- Interactive commands ---

cmd_detail() {
    local id="$1"
    local f
    f=$(feature_file "$id") || { echo -e "  ${RED}Feature '$id' not found${R}"; return; }

    echo ""
    echo -e "  ${BLD}Feature: $(feature_field "$f" "id")${R}"
    echo -e "  ${DIM}$(feature_field "$f" "name")${R}"
    echo ""

    # Full JSON
    echo -e "  ${DIM}--- feature file ---${R}"
    jq '.' "$f" 2>/dev/null | sed 's/^/  /'
    echo ""

    # Acceptance criteria with numbering
    local ac_count
    ac_count=$(jq '.acceptance_criteria | length' "$f" 2>/dev/null || echo 0)
    if [ "$ac_count" -gt 0 ]; then
        echo -e "  ${BLD}Acceptance criteria:${R}"
        jq -r '.acceptance_criteria[] // empty' "$f" 2>/dev/null | nl -ba -s '. ' | sed 's/^/    /'
        echo ""
    fi

    # Branch log
    local branch
    branch=$(feature_field "$f" "branch")
    if [ -n "$branch" ] && git rev-parse --verify "$branch" &>/dev/null; then
        echo -e "  ${BLD}Recent commits on ${CYN}${branch}${R}:"
        git log "$branch" --oneline -10 2>/dev/null | sed 's/^/    /'
        echo ""

        # Diff stats vs main
        local base
        base=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        if git rev-parse --verify "main" &>/dev/null; then
            base="main"
        fi
        echo -e "  ${BLD}Diff vs ${base}:${R}"
        git diff --stat "${base}...${branch}" 2>/dev/null | sed 's/^/    /'
        echo ""
    fi

    # Worktree
    if [ -n "$branch" ]; then
        local wt
        wt=$(worktree_for_branch "$branch")
        if [ -n "$wt" ]; then
            echo -e "  ${BLD}Worktree:${R} ${DIM}${wt}${R}"
        fi
    fi

    # PR
    if [ -n "$branch" ] && command -v gh &>/dev/null; then
        local pr_num
        pr_num=$(pr_for_branch "$branch")
        if [ -n "$pr_num" ]; then
            echo -e "  ${BLD}PR:${R} ${GRN}#${pr_num}${R}"
            gh pr view "$pr_num" --json title,state,additions,deletions,reviewDecision,url \
                --jq '"    \(.url)\n    +\(.additions) -\(.deletions)  \(.state)  review: \(.reviewDecision // "none")"' 2>/dev/null
        fi
    fi
    echo ""
}

cmd_log() {
    local id="$1"
    local f
    f=$(feature_file "$id") || { echo -e "  ${RED}Feature '$id' not found${R}"; return; }
    local branch
    branch=$(feature_field "$f" "branch")
    if [ -z "$branch" ] || ! git rev-parse --verify "$branch" &>/dev/null; then
        echo -e "  ${DIM}No branch for this feature${R}"
        return
    fi
    echo ""
    echo -e "  ${BLD}Commits on ${CYN}${branch}${R}:"
    git log "$branch" --oneline -20 2>/dev/null | sed 's/^/    /'
    echo ""
}

cmd_pr_open() {
    local id="$1"
    local f
    f=$(feature_file "$id") || { echo -e "  ${RED}Feature '$id' not found${R}"; return; }
    local branch
    branch=$(feature_field "$f" "branch")
    if [ -z "$branch" ]; then
        echo -e "  ${DIM}No branch for this feature${R}"
        return
    fi
    if ! command -v gh &>/dev/null; then
        echo -e "  ${RED}gh CLI not available${R}"
        return
    fi
    local pr_num
    pr_num=$(pr_for_branch "$branch")
    if [ -z "$pr_num" ]; then
        echo -e "  ${DIM}No open PR for branch ${branch}${R}"
        return
    fi
    echo -e "  Opening PR #${pr_num}..."
    gh pr view "$pr_num" --web 2>/dev/null
}

cmd_reset() {
    local id="$1"
    local f
    f=$(feature_file "$id") || { echo -e "  ${RED}Feature '$id' not found${R}"; return; }
    local current_status
    current_status=$(feature_field "$f" "status")

    echo -e "  ${YLW}Reset '${id}' from '${current_status}' to 'pending'?${R} [y/N] "
    read -r confirm
    if [[ "$confirm" != [yY] ]]; then
        echo -e "  ${DIM}Cancelled${R}"
        return
    fi

    # Clean up worktree if one exists
    local branch
    branch=$(feature_field "$f" "branch")
    if [ -n "$branch" ]; then
        local wt
        wt=$(worktree_for_branch "$branch")
        if [ -n "$wt" ]; then
            echo -e "  Removing worktree at ${wt}..."
            git worktree remove --force "$wt" 2>/dev/null || true
        fi
    fi

    # Update feature file
    local tmp
    tmp=$(mktemp)
    jq '.status = "pending" | .branch = "" | .notes = ""' "$f" > "$tmp" && mv "$tmp" "$f"
    echo -e "  ${GRN}Feature '${id}' reset to pending${R}"
}

cmd_done() {
    local id="$1"
    local f
    f=$(feature_file "$id") || { echo -e "  ${RED}Feature '$id' not found${R}"; return; }

    echo -e "  ${YLW}Mark '${id}' as complete?${R} [y/N] "
    read -r confirm
    if [[ "$confirm" != [yY] ]]; then
        echo -e "  ${DIM}Cancelled${R}"
        return
    fi

    local tmp
    tmp=$(mktemp)
    jq '.status = "complete"' "$f" > "$tmp" && mv "$tmp" "$f"
    echo -e "  ${GRN}Feature '${id}' marked complete${R}"
}

cmd_kill() {
    local id="$1"
    local f
    f=$(feature_file "$id") || { echo -e "  ${RED}Feature '$id' not found${R}"; return; }
    local branch
    branch=$(feature_field "$f" "branch")
    if [ -z "$branch" ]; then
        echo -e "  ${DIM}No branch for this feature${R}"
        return
    fi
    local wt
    wt=$(worktree_for_branch "$branch")
    if [ -z "$wt" ]; then
        echo -e "  ${DIM}No active worktree for branch ${branch}${R}"
        return
    fi

    echo -e "  ${RED}Remove worktree at ${wt}?${R} [y/N] "
    read -r confirm
    if [[ "$confirm" != [yY] ]]; then
        echo -e "  ${DIM}Cancelled${R}"
        return
    fi

    git worktree remove --force "$wt" 2>/dev/null && \
        echo -e "  ${GRN}Worktree removed${R}" || \
        echo -e "  ${RED}Failed to remove worktree${R}"
}

cmd_merge() {
    local id="$1"
    local f
    f=$(feature_file "$id") || { echo -e "  ${RED}Feature '$id' not found${R}"; return; }
    local branch
    branch=$(feature_field "$f" "branch")
    if [ -z "$branch" ]; then
        echo -e "  ${DIM}No branch for this feature${R}"
        return
    fi
    if ! command -v gh &>/dev/null; then
        echo -e "  ${RED}gh CLI not available${R}"
        return
    fi
    local pr_num
    pr_num=$(pr_for_branch "$branch")
    if [ -z "$pr_num" ]; then
        echo -e "  ${DIM}No open PR for branch ${branch}${R}"
        return
    fi

    echo -e "  ${YLW}Merge PR #${pr_num} for '${id}'?${R} [y/N] "
    read -r confirm
    if [[ "$confirm" != [yY] ]]; then
        echo -e "  ${DIM}Cancelled${R}"
        return
    fi

    gh pr merge "$pr_num" --merge 2>/dev/null && \
        echo -e "  ${GRN}PR #${pr_num} merged${R}" || \
        echo -e "  ${RED}Failed to merge PR #${pr_num}${R}"

    # Mark feature complete after merge
    local tmp
    tmp=$(mktemp)
    jq '.status = "complete"' "$f" > "$tmp" && mv "$tmp" "$f"
    echo -e "  ${GRN}Feature '${id}' marked complete${R}"
}

print_help() {
    echo ""
    echo -e "  ${BLD}Commands:${R}"
    echo -e "    ${CYN}d${R}  <feature>     Feature details (JSON, commits, diff stats, PR)"
    echo -e "    ${CYN}log${R} <feature>    Recent commits on the feature branch"
    echo -e "    ${CYN}pr${R} <feature>     Open the feature's PR in the browser"
    echo -e "    ${CYN}reset${R} <feature>  Reset feature to pending (clears branch and worktree)"
    echo -e "    ${CYN}done${R} <feature>   Mark feature as complete"
    echo -e "    ${CYN}kill${R} <feature>   Remove the feature's worktree"
    echo -e "    ${CYN}merge${R} <feature>  Merge the feature's PR and mark complete"
    echo -e "    ${CYN}r${R}               Refresh the display"
    echo -e "    ${CYN}q${R}               Quit"
    echo ""
}

# --- Main ---

if [ "$WATCH" = true ]; then
    trap 'printf "\033[?25h\033[?7h"; stty echo 2>/dev/null; exit 0' INT TERM
    printf '\033[?25l'  # hide cursor

    while true; do
        print_status

        # Show key hints
        echo -e "  ${DIM}d <id>${R} detail  ${DIM}pr <id>${R} open PR  ${DIM}merge <id>${R}  ${DIM}reset <id>${R}  ${DIM}q${R} quit"
        echo -e "  ${DIM}Refreshing in ${INTERVAL}s. Type a command or wait...${R}"

        # Wait for input with timeout -- if the user types something, handle it
        # instead of auto-refreshing
        cmd="" arg=""
        if read -r -t "$INTERVAL" cmd arg rest 2>/dev/null; then
            case "${cmd:-}" in
                q|quit|exit)
                    printf '\033[?25h'
                    exit 0
                    ;;
                r|refresh)   ;; # just loop and refresh
                d|detail)    printf '\033[?25h'; cmd_detail "${arg:-}"; printf '\033[?25l'
                             echo -e "  ${DIM}Press Enter to continue...${R}"; read -r ;;
                log)         printf '\033[?25h'; cmd_log "${arg:-}"; printf '\033[?25l'
                             echo -e "  ${DIM}Press Enter to continue...${R}"; read -r ;;
                pr)          cmd_pr_open "${arg:-}"
                             echo -e "  ${DIM}Press Enter to continue...${R}"; read -r ;;
                reset)       printf '\033[?25h'; cmd_reset "${arg:-}"; printf '\033[?25l'
                             echo -e "  ${DIM}Press Enter to continue...${R}"; read -r ;;
                done)        printf '\033[?25h'; cmd_done "${arg:-}"; printf '\033[?25l'
                             echo -e "  ${DIM}Press Enter to continue...${R}"; read -r ;;
                kill)        printf '\033[?25h'; cmd_kill "${arg:-}"; printf '\033[?25l'
                             echo -e "  ${DIM}Press Enter to continue...${R}"; read -r ;;
                merge)       printf '\033[?25h'; cmd_merge "${arg:-}"; printf '\033[?25l'
                             echo -e "  ${DIM}Press Enter to continue...${R}"; read -r ;;
                "")          ;; # Enter just refreshes
                *)           echo -e "  ${DIM}Unknown command '${cmd}'${R}"
                             sleep 1 ;;
            esac
        fi
        # Auto-refresh on timeout or after command
    done
else
    print_status
    print_help

    while true; do
        echo -ne "${DIM}>${R} "
        read -r cmd arg rest || break

        case "${cmd:-}" in
            q|quit|exit) break ;;
            r|refresh)   print_status; print_help ;;
            d|detail)    cmd_detail "${arg:-}" ;;
            log)         cmd_log "${arg:-}" ;;
            pr)          cmd_pr_open "${arg:-}" ;;
            reset)       cmd_reset "${arg:-}" ;;
            done)        cmd_done "${arg:-}" ;;
            kill)        cmd_kill "${arg:-}" ;;
            merge)       cmd_merge "${arg:-}" ;;
            h|help|"?")  print_help ;;
            "")          ;; # empty input, just re-prompt
            *)           echo -e "  ${DIM}Unknown command '${cmd}'. Type h for help.${R}" ;;
        esac
    done
fi
