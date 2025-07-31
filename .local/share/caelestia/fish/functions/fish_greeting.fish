function fish_greeting
    echo -ne '\x1b[38;5;16m'
    echo '    __  ___          _     '
    echo '   /  |/  /__ __ __ (_)_ __'
    echo '  / /|_/ / _ \\ \ // / // /'
    echo ' /_/  /_/\___/_\_\/_/\_,_/ '
    set_color normal
    if type -q fastfetch
        fastfetch --key-padding-left 5
    else
        echo "fastfetch is not installed."
    end
end
