# Visual: [/full/path][#?][exit-code?]
#        :
# Orange (#CB4B16, Solarized) brackets, white content, two-line layout.
# Translated from a former Oh My Posh theme (woofle.omp.json).

function fish_prompt
    set -l last_status $status
    set -l reset (set_color normal)
    set -l orange (set_color CB4B16)
    set -l white (set_color FFFFFF)

    # Full path with ~ substitution (OMP's path "style: full" equivalent).
    set -l path (string replace -r "^$HOME" '~' $PWD)
    echo -n -s $orange'['$white$path$orange']'$reset

    if fish_is_root_user
        # OMP theme used empty brackets `[]` as the root indicator; preserved as-is.
        echo -n -s $orange'[]'$reset
    end

    if test $last_status -ne 0
        echo -n -s $orange'['$white$last_status$orange']'$reset
    end

    echo
    echo -n -s $orange':'$reset' '
end
