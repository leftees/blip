#!/bin/bash

set -euo pipefail
source /usr/lib/blip.bash

main () {
    local name="$(get_gecos_name)"
    if get_user_confirmation "Is your name $name?" ; then
        echo "Nice to meet you $name."
    else
        echo "I'll just call you $(get_username) then."
    fi
}

main "$@"

