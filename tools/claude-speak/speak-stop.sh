#!/bin/bash
# Stop Claude's reply being read aloud. Runs from the UserPromptSubmit hook (so
# sending a message cuts the old reply off) and from a global hotkey, see README.md.
killall say 2>/dev/null
exit 0
