# Silence the welcome message.
set -g fish_greeting

# Activate zoxide
if type -q zoxide
    zoxide init fish | source
end

# add .local/bin to the $PATH
test -d $HOME/.local/bin; or mkdir -p $HOME/.local/bin
fish_add_path $HOME/.local/bin

# .net setup
set -gx DOTNET_ROOT $HOME/.dotnet
set -gx DOTNET_CLI_TELEMETRY_OPTOUT 1
fish_add_path $HOME/.dotnet
