#!/usr/bin/env bash
set -euo pipefail

SESSION_NAME="postgrest_demo"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux is not installed."
  echo "Run the demo manually in 3 terminals:"
  echo "  1) bash demo/03_walkthrough.sh"
  echo "  2) bash demo/01_watch_logs.sh"
  echo "  3) bash demo/02_watch_db_state.sh"
  exit 1
fi

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  tmux kill-session -t "$SESSION_NAME"
fi

tmux new-session -d -s "$SESSION_NAME" "bash demo/03_walkthrough.sh; echo; echo 'Walkthrough finished. Press Enter to close this pane.'; read -r"
tmux split-window -h -t "$SESSION_NAME:0" "bash demo/01_watch_logs.sh"
tmux split-window -v -t "$SESSION_NAME:0.1" "bash demo/02_watch_db_state.sh"
tmux select-layout -t "$SESSION_NAME:0" tiled
tmux select-pane -t "$SESSION_NAME:0.0"

echo "Launching tmux demo session: $SESSION_NAME"
tmux attach -t "$SESSION_NAME"
