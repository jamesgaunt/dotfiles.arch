

generate_ssh_key() {
    display_header "Generating SSH Key"

    local key="$HOME/.ssh/id_ed25519"
    [[ -f "$key" ]] && return 0   # already exists, don't clobber
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "james.gaunt@webfuel.com" -f "$key" -N ""

    echo "Add this public key to GitHub (Settings → SSH and GPG keys):"
    cat "$key.pub"
    echo "Then repoint dotfiles: git -C \"\$HOME/dotfiles\" remote set-url origin git@github.com:jamesgaunt/dotfiles.arch.git"
}

# Outputs a key to authenticate with github
generate_ssh_key

# git -C "$HOME/dotfiles" remote set-url origin git@github.com:jamesgaunt/dotfiles.arch.git
