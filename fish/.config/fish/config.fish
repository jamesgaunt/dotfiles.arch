# Silence the welcome message.
set -g fish_greeting

# Activate zoxide
if type -q zoxide
    zoxide init fish | source
end

fish_add_path $HOME/.local/bin

# .net setup
set -gx DOTNET_ROOT $HOME/.dotnet
set -gx DOTNET_CLI_TELEMETRY_OPTOUT 1
fish_add_path $HOME/.dotnet
