# Persist bash history across container rebuilds.
#
# HISTFILE points at the `command-history` named volume (mounted at /commandhistory
# in devcontainer.json), so arrow-up recall survives "Rebuild Container" and stays
# scoped to this repo. The postCreateCommand appends this file to ~/.bashrc once.
#
# NOTE: assumes bash is the container's default shell (it is for the
# javascript-node devcontainer image + VS Code's integrated terminal). If you
# switch the container to zsh, the zsh equivalent is needed in ~/.zshrc instead.

export HISTFILE=/commandhistory/.bash_history
export HISTSIZE=100000          # commands kept in the running shell's memory
export HISTFILESIZE=200000      # commands kept on disk
export HISTCONTROL=ignoreboth   # drop duplicate and space-prefixed commands
export HISTTIMEFORMAT='%F %T '  # timestamp each entry
shopt -s histappend             # append on exit instead of overwriting the file

# Flush every command to HISTFILE immediately, so history is not lost if the
# container stops without a clean shell exit. Preserve any PROMPT_COMMAND the base
# image already set, and don't stack "history -a" if it is already present.
case "$PROMPT_COMMAND" in
  *"history -a"*) ;;
  *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a" ;;
esac
