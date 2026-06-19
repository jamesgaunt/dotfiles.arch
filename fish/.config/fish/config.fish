# Silence the welcome message.
set -g fish_greeting

# Activate zoxide
if type -q zoxide
    zoxide init fish | source
end

export PATH="$HOME/.local/bin:$PATH"
