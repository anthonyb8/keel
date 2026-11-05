# Shell side of keel: th, thr, tt and ttr on keel. Source it from .zshrc only
# at the switch (row 12); until then harness.zsh defines the same names.

export PATH="$HOME/.local/bin:$PATH"

# th <branch> [base]   lease a pool worktree on a new branch and cd into it.
# The base defaults to the one the repository's pack names, else treehouse's
# own default for the repository. treehouse refuses a base it cannot resolve
# before it leases anything, so a typo never holds a slot.
th() {
  if [[ -z "$1" ]]; then
    print -u2 "usage: th <branch> [base]"
    return 2
  fi
  local base="${2:-$(keel base)}" wt
  local args=(get --lease --lease-holder "${TREEHOUSE_LEASE_HOLDER:-$USER}" --branch "$1")
  [[ -n "$base" ]] && args+=(--base "$base")
  wt=$(treehouse "${args[@]}") || return
  cd "$wt"
}

# thr [path]   return a worktree to the pool, stepping back to the main
# checkout first so return does not terminate the shell standing in it, and
# stopping and releasing the tree's stack so neither a dev server nor a
# database outlives the tree.
thr() {
  local wt="${1:-$PWD}" common
  (cd "$wt" && keel stack down && keel stack release)
  common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
    cd "${common:h}"
  treehouse return "$wt"
}

# _th_leased   one tab-separated row per leased tree for the pickers below:
# name, branch, holder, "running" where a process (stack, dev server) is up,
# then the path, which fzf hides.
_th_leased() {
  treehouse status --json |
    jq -r '.[] | select(.status == "leased")
      | [.name,
         (if .branch == "" then "(detached)" else .branch end),
         .lease_holder,
         (if (.processes | length) > 0 then "running" else "" end),
         .path] | @tsv'
}

# tt [query]   cd into a leased tree, picked by number, branch, issue ID or
# holder. A query matching one tree jumps straight in; otherwise fzf lists them.
# The variable is `dir`, never `path`: zsh ties `path` to $PATH.
tt() {
  local dir
  dir=$(
    _th_leased |
      fzf --exact --delimiter='\t' --with-nth=1,2,3,4 --query="$*" \
          --select-1 --exit-0 --height=40% --reverse |
      cut -f5
  ) || return
  [[ -n $dir ]] && cd "$dir"
}

# ttr [query]   return leased trees to the pool, picked like tt. Tab marks
# several. Unlike tt, a single match still shows the list, and it asks once
# before returning anything; each tree then goes through thr, so its stack
# stops and treehouse still confirms before discarding uncommitted changes.
ttr() {
  local -a dirs
  dirs=(${(f)"$(
    _th_leased |
      fzf --multi --exact --delimiter='\t' --with-nth=1,2,3,4 --query="$*" \
          --exit-0 --height=40% --reverse --header='tab marks, enter returns' |
      cut -f5
  )"})
  (( ${#dirs} )) || return
  print -l -- $dirs
  read -q "?Return ${#dirs} tree(s) to the pool? [y/N] " || { print; return 1 }
  print
  local dir
  for dir in $dirs; do
    thr "$dir"
  done
}
