#!/bin/bash
#
# blip - Bash Library for Indolent Programmers
#
# Please see the man page blip.bash(3) or bash.pod for full documentation.
#
# This library is written for, and requires the bash shell. It is not expected
# to, nor intended to work with the bourne shell or any other shell. Great care
# has been taken to use internal built-in functions instead of forking external
# commands wherever possible, in order to offer the best performance possible.
#
# https://nicolaw.uk/blip
# https://github.com/neechbear/blip/
# https://github.com/neechbear/blip/blob/master/blip.bash.pod
#
# MIT License
#
# Copyright (c) 2016 Nicola Worthington
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Some inspirational sources:
#   https://nicolaw.uk/bash
#   http://mywiki.wooledge.org/BashFAQ
#   https://code.google.com/archive/p/bsfl/downloads
#   https://bash.cyberciti.biz/guide/Shell_functions_library
#   http://www.bashinator.org/
#   https://dberkholz.com/2011/04/07/bash-shell-scripting-libraries/
#   https://github.com/Dieterbe/libui-sh/blob/master/libui.sh
#
# Get a nice list of bash built-ins without forking crap for formatting:
#     while read -r _ cmd ; do echo $cmd ; done < <(enable -a)
#
# Preferred function naming conventions:
#   is_*    An evaluation test that returns boolean true or false only.
#           No STDOUT should be emitted.
#
#   to_*    Data manipulation that returns results through STDOUT.
#
#   get_*   Gathers some information which is returned through STDOUT.
#           Newline characters should be omitted from output when only
#           a single line of output is ever expected.

# Action to take on fatal conditions. Test is written in old bourne compatible
# syntax to account for old limited and buggy conditionals.
if [ "x${BLIP_INTERNAL_FATAL_ACTION:-}" = "x" ] ; then
    BLIP_INTERNAL_FATAL_ACTION="exit 2"
fi

# Try and bail out early if we detect that we are probably not running
# from inside a bash shell interpreter. You may disable the exit on
# non-Bash shell functionality by setting BLIP_ALLOW_FOREIGN_SHELLS=1.
if [ "x$BASH" = "x" ] || [ "x$BASH_VERSION" = "x" ] || [ "x$BASHPID" = "x" ] ; then
    case "x$BLIP_ALLOW_FOREIGN_SHELLS" in
        x1|xyes|xtrue|xon|xenable|xenabled) true ;;
        *)
            echo "blip.bash detected a foreign shell interpreter is running;" \
                 "exiting!" >&2
            $BLIP_INTERNAL_FATAL_ACTION
    esac
fi

# TODO(nicolaw): Work out how to automatically populate these values at build
#                and release (packaging) time.
if [[ -z "${BLIP_VERSION:+defined}" ]] ; then
    declare -rxg BLIP_VERSION="0.4-1-alpha"
    declare -rxga BLIP_VERSINFO=("0" "4" "1" "alpha")
else
    echo "blip.bash version $BLIP_VERSION is already loaded." >&2
    if ! [[ "$BLIP_VERSION" = "0.4-1-alpha" ]] ; then
        echo "Reloading conflicting versions of blip.bash over each" \
            "other may result in unpredictable behaviour!" >&2
    fi
fi

# Evaulates if single argument input is an integer.
is_int () { [[ "${1:-}" =~ ^-?[0-9]+$ ]]; }
is_integer () { is_int "$@"; }

# This is only used internally if you want to debug something. It allows
# printing of some useful messages in the more complex functions like
# trap handlers.
declare -igx BLIP_DEBUG_LOGLEVEL=${BLIP_DEBUG_LOGLEVEL:-0}
if ! is_int "$BLIP_DEBUG_LOGLEVEL" ; then
    BLIP_DEBUG_LOGLEVEL=0
fi

if [[ -n "${BLIP_REQUIRE_VERSION:-}" ]] ; then
    declare -ax BLIP_REQUIRE_VERSINFO=(${BLIP_REQUIRE_VERSION//[-.]/ })
    if   [[ ${BLIP_REQUIRE_VERSINFO[0]:-} -gt ${BLIP_VERSINFO[0]} ]] \
      || [[ ${BLIP_REQUIRE_VERSINFO[1]:-} -gt ${BLIP_VERSINFO[1]} ]] \
      || [[ ${BLIP_REQUIRE_VERSINFO[2]:-} -gt ${BLIP_VERSINFO[2]} ]] ; then
        echo "blip.bash version $BLIP_VERSION does not satisfy minimum" \
             "required version $BLIP_REQUIRE_VERSION; exiting!" >&2
        $BLIP_INTERNAL_FATAL_ACTION
    fi
    unset BLIP_REQUIRE_VERSIFO
fi

# Assign command names to run from $PATH unless otherwise already defined.
declare -gx BLIP_EXTERNAL_CMD_FLOCK="${BLIP_EXTERNAL_CMD_FLOCK:-flock}"
declare -gx BLIP_EXTERNAL_CMD_STAT="${BLIP_EXTERNAL_CMD_STAT:-stat}"
declare -gx BLIP_EXTERNAL_CMD_BC="${BLIP_EXTERNAL_CMD_BC:-bc}"
declare -gx BLIP_EXTERNAL_CMD_CURL="${BLIP_EXTERNAL_CMD_CURL:-curl}"
declare -gx BLIP_EXTERNAL_CMD_DATE="${BLIP_EXTERNAL_CMD_DATE:-date}"
declare -gx BLIP_EXTERNAL_CMD_GREP="${BLIP_EXTERNAL_CMD_GREP:-grep}"

# TOOD(nicolaw): Decide if individually exported environment variables are best
#                or if an associative array is more convenient. The associative
#                array is certianly cleaner, but it cannot be exported to sub-
#                shells, which makes it less flexible.
#while read -r _ _blip_vtype _blip_vname ; do
#    if [[ ! "$_blip_vtype" =~ A ]] && \
#       [[ "$_blip_vname" = "BLIP_EXTERNAL_CMD" ]] ; then
#        unset BLIP_EXTERNAL_CMD
#    fi
#done < <(typeset -p BLIP_EXTERNAL_CMD 2>/dev/null||:)
#declare -p BLIP_EXTERNAL_CMD >/dev/null 2>&1 || declare -Agx BLIP_EXTERNAL_CMD=()
#for _ in flock stat bc curl date grep egrep ; do
#    BLIP_EXTERNAL_CMD[$_]="$_"
#done

# Trap handler stack.
declare -gxa BLIP_TRAP_STACK=()
declare -gxA BLIP_TRAP_MAP=() # Maps BLIP_TRAP_STACK indexes to signals

# The following may or may not offer a better solution. I should read it in
# detail to find out if I should rewrite what I've already done or not. At
# first glance it looks concise, but there's a fair few evals and it doesn't
# look set -u friendly.
# Either way, I like the idea of being able to prepend as well as just being
# able to append (push) handlers on and off the stack. I need to implement
# that functionality too! I may need to rethink the names of my functions
# though.
# http://stackoverflow.com/questions/16115144/bash-save-and-restore-trap-state-easy-way-to-manage-multiple-handlers-for-trap

append_trap () {
  declare action="${1:-}"; shift
  [[ -z "$action" ]] && return
  declare sig
  for sig in "$@" ; do
    trap -- "$(
          _get_existing_action() { printf "%s${3+\n}" "${3:-}"; }
          eval "_get_existing_action $(trap -p "$sig")"
          printf '%s\n' "$action"
        )" "$sig"
  done
}
declare -ft append_trap

execute_trap_stack () {
  declare sig
  for sig in "$@" ; do
    if [[ -n "${BLIP_TRAP_MAP[$sig]:-}" ]] ; then
      declare -i idx
      for idx in ${BLIP_TRAP_MAP[$sig]} ; do
        eval "${BLIP_TRAP_STACK[$idx]}"
      done
    fi
  done
}

push_trap_stack () {
    declare action="${1:-}"; shift
    [[ -z "$action" ]] && return

    declare sig
    for sig in "$@" ; do
        declare -i idx="${#BLIP_TRAP_STACK[@]}"
        declare -i i
        for ((i = 0; i < ${#BLIP_TRAP_STACK[@]}; i++)) ; do
            if [[ -z "${BLIP_TRAP_STACK[$i]:-}" ]] ; then
                idx=$i
                break
            fi
        done

        BLIP_TRAP_STACK[$idx]=$action
        if [[ -n "${BLIP_TRAP_MAP[$sig]:+defined}" ]] ; then
            BLIP_TRAP_MAP[$sig]+=" $idx"
        else
            BLIP_TRAP_MAP[$sig]="$idx"
            if ! [[ "$(trap -p "$sig")" =~ execute_trap_stack\ $sig ]] ; then
                append_trap "execute_trap_stack $sig" "$sig"
            fi
        fi

        if [[ $BLIP_DEBUG_LOGLEVEL -ge 1 ]] ; then
            for ((i = 0; i < ${#BLIP_TRAP_STACK[@]}; i++)) ; do
                echo "\$BLIP_TRAP_STACK[$i]=${BLIP_TRAP_STACK[$i]:-}"
            done
            echo "\$BLIP_TRAP_MAP[$sig]=${BLIP_TRAP_MAP[$sig]:-}"
        fi
        if [[ $BLIP_DEBUG_LOGLEVEL -ge 3 ]] ; then
            trap -p "$sig" || true
        fi
    done
}

pop_trap_stack () {
  declare sig
  for sig in "$@" ; do
    if [[ -n "${BLIP_TRAP_MAP[$sig]:-}" ]] ; then
      declare -a map=(${BLIP_TRAP_MAP[$sig]})
      declare -i idx=${map[-1]}
      BLIP_TRAP_STACK[$idx]=""
      unset map[${#map[@]}-1]
      BLIP_TRAP_MAP[$sig]="${map[*]}"
    fi

    if [[ $BLIP_DEBUG_LOGLEVEL -ge 1 ]] ; then
      echo "\$BLIP_TRAP_MAP[$sig]=${BLIP_TRAP_MAP[$sig]:-}"
      declare -i i
      for ((i = 0; i < ${#BLIP_TRAP_STACK[@]}; i++)) ; do
        echo "\$BLIP_TRAP_STACK[$i]=${BLIP_TRAP_STACK[$i]:-}"
      done
    fi
    if [[ $BLIP_DEBUG_LOGLEVEL -ge 3 ]] ; then
      trap -p "$sig" || true
    fi
  done
}

set_trap_stack () {
  declare action="${1:-}"; shift
  [[ -z "$action" ]] && return
  declare sig
  for sig in "$@" ; do
    unset_trap_stack "$sig"
    push_trap_stack "$action" "$sig"
  done
}

unset_trap_stack () {
  declare sig
  for sig in "$@" ; do
    if [[ -n "${BLIP_TRAP_MAP[$sig]:-}" ]] ; then
      declare -i idx
      for idx in ${BLIP_TRAP_MAP[$sig]} ; do
        BLIP_TRAP_STACK[$idx]=""
      done
      unset BLIP_TRAP_MAP[$sig]
    fi
  done
}

get_trap_stack () {
  declare sig
  for sig in "$@" ; do
    if [[ -n "${BLIP_TRAP_MAP[$sig]:-}" ]] ; then
      declare -i i
      for i in ${BLIP_TRAP_MAP[$sig]} ; do
        if [[ -n "${BLIP_TRAP_STACK[$i]:-}" ]] ; then
          printf '%s\n' "${BLIP_TRAP_STACK[$i]:-}"
        fi
      done
    fi
    return 0
  done
}

get_variable_type () {
  declare vtype="$(declare -p "$1" 2>/dev/null)"
  vtype="${vtype#* -}"
  printf '%s' "${vtype%% *}"
}

as_json_value () {
  if [[ ! -n "${1+defined}" ]] ; then
    # null.
    printf 'null'
  elif [[ "$1" = "true" || "$1" = "false" ]] ; then
    # Boolean.
    printf '%s' "$1"
  elif [[ "$1" =~ ^-?([1-9][0-9]*|0)(\.[0-9]+)?$ ]] ; then
    # TODO(nicolaw): Allow support for exponential E notation.
    # Number.
    printf '%s' "$1"
  else
    # String.
    printf '"%s"' "$(as_json_string "$1")"
  fi
}

as_json_string () {
  declare str="$1"
  # shellcheck disable=SC1003
  declare -a shell=(        '\'  '"'  $'\b' $'\f' $'\n' $'\r' $'\t' )
  declare -a json_escaped=( '\\' '\"'  '\b'  '\f'  '\n'  '\r'  '\t' )
  declare -i i
  for i in "${!shell[@]}"; do
    str="${str//"${shell[${i}]}"/${json_escaped[${i}]}}"
  done
  printf '%s' "$str"
}

# vars_as_json $(compgen -v BASH)
vars_as_json () {
  declare format='"%s": %s'
  printf '{'
  while [[ $# -ge 1 ]] ; do
    declare vtype="$(get_variable_type "$1")"

    if [[ $vtype == *"a"* ]] ; then
      # Array.
      declare tmp_indirection="${1}[@]"
      declare -a tmp_array=( "${!tmp_indirection}" )
      # shellcheck disable=SC2059
      printf "$format" "$1" '['
      declare -i i
      for i in "${!tmp_array[@]}" ; do
        printf '%s' "$(as_json_value ${tmp_array[$i]+"${tmp_array[$i]}"})"
        if [[ $i -lt ${#tmp_array} ]] ; then
          printf ', '
        fi
      done
      printf ']'

    elif [[ $vtype == *"A"* ]] ; then
      # Associative array / object.
      declare tmp_indirection="$(declare -p "$1")"
      unset __blip_tmp_dict
      # Even though this declare works exactly as-is on the command line, even
      # including all the indirection, it doesn't appear to properly work here.
      # We appear to be able to get the values out of the dict, but not the
      # keys, and not print it's declare statement etc.
      eval "declare -A __blip_tmp_dict=${tmp_indirection#*=}"
      if [[ $BLIP_DEBUG_LOGLEVEL -ge 3 ]] ; then
        declare -p "__blip_tmp_dict" >&2 || :
        echo "__blip_tmp_dict keys=${!__blip_tmp_dict[@]}" >&2
        echo "__blip_tmp_dict values=${__blip_tmp_dict[@]}" >&2
      fi
      # shellcheck disable=SC2059
      printf "$format" "$1" '{'
      declare -i i=0
      declare k
      for k in "${!__blip_tmp_dict[@]}" ; do
        # shellcheck disable=SC2059,SC2086
        printf "$format" "$i" "$(as_json_value ${__blip_tmp_dict[$i]+"${__blip_tmp_dict[$i]}"})"
        if [[ $k -lt ${#__blip_tmp_dict[@]} ]] ; then
          printf ', '
        fi
        let i++
      done
      printf '}'
      unset __blip_tmp_dict

    else
      # Number, string, boolean, null.
      # shellcheck disable=SC2059,SC2086
      printf "$format" "$1" "$(as_json_value ${!1:+"${!1}"})"
    fi

    if [[ $# -gt 1 ]] ; then
      printf ', '
    fi
    shift
  done
  printf '}\n'
}

is_newer_version () {
  declare lhs_version="${1:-}"
  declare rhs_version="${2:-}"
  declare -a lhs=( ${lhs_version//./ } )
  declare -a rhs=( ${rhs_version//./ } )
  declare -i i
  for i in "${!lhs[@]}" ; do
    if ! [[ ${rhs[$i]:-} -ge ${lhs[$i]} ]] ; then
      return 1
    fi
  done
  return 0
}

required_command_version () {
    declare command="$1"
    declare check_version="$2"
    declare version_command="${3:-${command} --version}"
    is_newer_version "$check_version" "$($version_command 2>&1 | egrep -ow '[0-9]+\.[0-9\.]+' | tail -n1)"
}

get_pid_lock_filename () {
    declare lock_path="${1:-}"
    declare base_name="${2:-$0}"
    declare tmp_dir="${TMPDIR:-/tmp}"

    if [[ -z "$lock_path" ]] ; then
        if [[ -w /var/run ]] ; then
            lock_path="/var/run"
        elif [[ -n "${tmp_dir:-}" ]] && [[ -w "$tmp_dir" ]] ; then
            lock_path="$tmp_dir"
        else
            lock_path="${PWD:-./}"
        fi
    fi

    base_name="${base_name##*/}"
    if [[ "$base_name" =~ ([a-zA-Z0-9][a-zA-Z0-9_-]*) ]] ; then
        echo -n "${lock_path%/}/${BASH_REMATCH[1]}.pid"
    else
        echo -n "${lock_path%/}/${base_name}.pid"
    fi
}

get_exclusive_execution_lock () {
    declare pid_file="${1:get_pid_lock_filename}"
    # Use prefered flock mechanism (probably under Linux).
    if is_in_path "$BLIP_EXTERNAL_CMD_FLOCK" ; then
        : "${pid_file}"
    # Otherwise make do with mkdir method.
    else
        : "${pid_file}"
    fi
}

read_config_file () {
    declare config_file="${1:-}"; shift
    _safe_read_vars () {
        declare input_file="$1"
        (
            source "$input_file" || :
            for var in "$@" ; do
                printf '%q' "${var}=${!var:-}"
                echo
            done
        ) || :
    }
    while read -r line ; do
        declare "$(eval "echo ${line}")" || :
    done < <(_safe_read_vars "$config_file")
}

# Return the length of the longest argument.
get_max_length () {
    declare -i max=0
    for arg in "$@" ; do
        if [[ ${#arg} -gt $max ]] ; then
            max="${#arg}"
        fi
    done
    echo -n "$max"
}

trim () {
    declare string="${1:-}"
    string="${string#"${string%%[![:space:]]*}"}"
    string="${string%"${string##*[![:space:]]}"}"
    echo -n "$string"
}

get_string_characters () {
    declare string="${1:-}"
    declare -i i
    for (( i=0; i<${#string}; i++ )); do
      echo "${string:$i:1}"
    done
}

# Functionality to add:
#    - Add get_user_input() - multi character user input without defaults
#    - Add process locking functions
#    - Add background daemonisation functions (ewww - ppl should use systemd)
#    - Add standard logging functions
#    - Add syslogging functionality of all process STDOUT + STDERR
#    - Add console colour output options

# Ask the user for confirmation, expecting a single character y or n reponse.
# Returns 0 when selecting y, 1 when selecting n.
get_user_confirmation () {
    declare question="${1:-Are you sure?}"
    declare default_response="${2:-}"
    get_user_selection "$question" "$default_response" "y" "n"
}

# See also: bash's "select" built-in.
get_user_selection () {
    declare question="${1:-Make a selection }"; shift
    declare default_response="${1:-}"; shift
    declare -i max_response_length="$(get_max_length "$@")"

    # Replace with a standard argument validation routine.
    # http://tldp.org/LDP/abs/html/exitcodes.html
    if [[ $max_response_length -ne 1 ]] ; then
        >&2 echo "get_user_selection() <question_prompt> <default_response> <valid_responseN>..."
        >&2 echo "No valid_reponse arguments were passed, or 1 or more valid_response arguments were not exactly 1 character in length."
        return 126
    fi

    declare prompt=""
    declare arg
    for arg in "$@" ; do
        if [[ "$arg" = "$default_response" ]] ; then
            arg="*$arg"
        fi
        prompt="${prompt:+$prompt|}$arg"
    done

    declare input=""
    while read -n 1 -e -r -p "${question}${prompt:+ [$prompt]: }" input ; do
        if [[ -z "$input" ]] ; then
            input="$default_response"
        fi

        declare -i rc=0
        for valid_response in "$@" ; do
            if [[ "$input" = "$valid_response" ]] ; then
                return $rc
            fi
            rc=$((rc+1))
        done
    done
}

# Store the time that bash started (or a close enough aproximation assuming
# that nobody has modified $SECONDS if we're using an older version of bash).
if ! [[ -n "${BLIP_START_UNIXTIME+defined}" ]] ; then
    if [[ ${BASH_VERSINFO[0]} -ge 4 && ${BASH_VERSINFO[1]} -ge 2 ]] ; then
        declare -xrgi BLIP_START_UNIXTIME="$(printf "%(%s)T" -2)"
    else
        declare -xrgi BLIP_START_UNIXTIME="$(( $(date +"%s") - SECONDS ))"
    fi
fi

# https://en.wikipedia.org/wiki/ISO_8601
get_iso8601_date () { get_date "%Y-%m-%d" "$@"; }

# Return the time since the epoch in seconds.
get_unixtime () { get_date "%s" "$@"; }

# This is pretty pointless (just use $SECONDS right?).
#if [[ ${BASH_VERSINFO[0]} -ge 4 && ${BASH_VERSINFO[1]} -ge 2 ]] ; then
#get_runtime_seconds () {
#    echo -n $(( $(get_unixtime -1) - $(get_unixtime -2) ))
#}
#fi

get_date () {
    declare format="${1:-%a %b %d %H:%M:%S %Z %Y}"
    declare when="${2:--1}"
    if [[ ${BASH_VERSINFO[0]} -ge 4 && ${BASH_VERSINFO[1]} -ge 2 ]] ; then
        printf "%($format)T\n" "$when"
    else
        if [[ "$when" = "-1" ]] ; then
            when=""
        elif [[ "$when" = "-2" ]] ; then
            when="@${BLIP_START_UNIXTIME}"
        fi
        $BLIP_EXTERNAL_CMD_DATE ${when:+-d "$when"} +%s
    fi
}

url_http_header () {
    $BLIP_EXTERNAL_CMD_CURL -k -L -s -I "$1"
}

# 200 OK
# Returns "200"
url_http_response_code () {
    declare url="$1"
    declare response="$(url_http_response "$url")"
    if [[ "$response" =~ ([0-9]+) ]] ; then
        echo -n "${BASH_REMATCH[1]}"
    fi
}

# HTTP/1.1 200 OK
# Returns "200 OK"
url_http_response () {
    declare url="$1"
    declare header=""
    declare response=""
    while read -r header ; do
        if [[ "$header" =~ ^HTTP(/[0-9]*\.?[0-9]+)?\ +([[:print:]]+) ]] ; then
            response="${BASH_REMATCH[2]}"
        fi
    done < <(url_http_header "$url")
    [[ -n "$response" ]] && echo -n "$response"
}

# TODO(nicolaw): Make less broken; what about non-http:// and file:// URLs?
url_exists () {
    declare url="$1"
    if [[ "$url" =~ ^file:// ]] ; then
        $BLIP_EXTERNAL_CMD_CURL -k -s -L -I "$url" -o /dev/null 2>/dev/null
    else
        declare response="$(url_http_response_code "$url")"
        if     is_int "$response" \
            && [[ $response -ge 200 ]] \
            && [[ $response -lt 300 ]] ; then
                return 0
        fi
    fi
    return 1
}

is_in_path () {
    declare cmd
    for cmd in "$@" ; do
        if ! type -P "$cmd" >/dev/null 2>&1 ; then
             return 1
        fi
    done
    return 0
}

# MAC-48 and EUI-48 are syntactically indistinguishable, so for the sake of
# consistency this is named is_eui48_address to match the eui64 function.
is_eui48_address () {
    declare addr="${1:-}"
    addr="${addr,,}"
    if   [[ $addr =~ ^[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}$ ]] ; then
        return 0
    elif [[ $addr =~ ^[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}$ ]] ; then
        return 0
    elif [[ $addr =~ ^[a-f0-9]{4}\.[a-f0-9]{4}\.[a-f0-9]{4}$ ]] ; then
        return 0
    fi
    return 1
}

is_eui64_address () {
    declare addr="${1:-}"
    addr="${addr,,}"
    if   [[ $addr =~ ^[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}$ ]] ; then
        return 0
    elif [[ $addr =~ ^[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}-[a-f0-9]{2}$ ]] ; then
        return 0
    fi
    return 1
}

# IEEE 802 standard format for MAC-48 and EUI-48  addresses in most
# common human friendly transmission order.
is_mac_address () { is_eui48_address "$@"; }

# TODO(nicolaw): Try to get this working using bash's own regex engine.
is_ipv4_address () {
    declare regex='(?<![0-9])(?:(?:[0-1]?[0-9]{1,2}|2[0-4][0-9]|25[0-5])[.](?:[0-1]?[0-9]{1,2}|2[0-4][0-9]|25[0-5])[.](?:[0-1]?[0-9]{1,2}|2[0-4][0-9]|25[0-5])[.](?:[0-1]?[0-9]{1,2}|2[0-4][0-9]|25[0-5]))(?![0-9])'
    $BLIP_EXTERNAL_CMD_GREP -Pq "^$regex$" <<< "${1:-}"
}

is_ipv4_prefix () {
    declare ip="${1%%/*}"
    declare prefix="${1##*/}"
    if is_ipv4_address "$ip" && is_int "$prefix" &&
        [[ $prefix -ge 0 ]] && [[ $prefix -le 32 ]] ; then
        return 0
    fi
    return 1
}

# TODO(nicolaw): Try to get this working using bash's own regex engine.
is_ipv6_address () {
    declare regex='((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?'
    $BLIP_EXTERNAL_CMD_GREP -Pq "^$regex$" <<< "${1:-}"
}

is_ipv6_prefix () {
    declare ip="${1%%/*}"
    declare prefix="${1##*/}"
    if is_ipv6_address "$ip" && is_int "$prefix" &&
        [[ $prefix -ge 0 ]] && [[ $prefix -le 128 ]] ; then
        return 0
    fi
    return 1
}

get_free_disk_space () {
    while read -r _ blocks _ ; do
        if is_int "$blocks" ; then
            echo "$(( blocks * 1024 ))"
        fi
    done < <(df -kP "$1")
}

get_username () {
    declare user="${USER:-$LOGNAME}"
    user="${user:-$(id -un)}"
    echo "${user:-$(whoami)}"
}

get_gecos_name () {
    get_gecos_info "name" "$@"
}

# https://en.wikipedia.org/wiki/Gecos_field
get_gecos_info () {
    declare key="${1:-}"
    declare user="${2:-$(get_username)}"
    #while IFS=: read username passwd uid gid gecos home shell ; do
    while IFS=: read username _ _ _ gecos _ _ ; do
        if [[ "$user" = "$username" ]] ; then
            if [[ -n "$key" ]] && [[ "$gecos" =~ ([,;]) ]] ; then
                IFS="${BASH_REMATCH[1]}" read name addr office home email <<< "$gecos"
                case "$key" in
                    *name) echo "$name" ;;
                    building|room|addr*) echo "$addr" ;;
                    office*) echo "$office" ;;
                    home*) echo "$home" ;;
                    *) echo "$email" ;;
                esac
            elif [[ -z "$key" ]] || [[ "$key" = "name" ]] ; then
                echo "$gecos"
            fi
            break
        fi
    done < <(getent passwd "$user")
}

# English language boolean true or false.
is_true () { [[ "${1:-}" =~ ^yes|on|enabled?|true|1$ ]]; }
is_false () { [[ "${1:-}" =~ ^no|off|disabled?|false|0$ ]]; }
is_boolean () { is_true "$@" || is_false "$@"; }

# Evaluates if single argument input is an absolute integer.
is_abs_int () { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
is_absolute_integer () { is_abs_int "$@"; }

is_zero () { [[ "${1:-}" =~ ^[-\+]?0*\.?0+$ ]]; }
is_negative () { [[ "${1:-}" =~ ^-[0-9]*\.?[0-9]+$ ]] && [[ "${1:-}" =~ [1-9] ]]; }
is_positive () { [[ "${1:-}" =~ ^\+?[0-9]*\.?[0-9]+$ ]] && [[ "${1:-}" =~ [1-9] ]]; }

is_float () { [[ "${1:-}" =~ ^[-\+]?[0-9]*\.[0-9]+$ ]]; }

# Converts single argument input to an absolute value.
abs () {
    declare val="${1:-}"
    if is_positive "$val" || is_zero "$val" ; then
        echo -n "$val"
    elif is_int "$val" ; then
        echo -n $(( val * -1 ))
    elif is_float "$val" ; then
        $BLIP_EXTERNAL_CMD_BC <<< "$val * -1"
    else
        return 2
    fi
}
absolute () { abs "$@"; }

# Convert one or more words to uppercase without explicit variable substition.
# (Not meant as a replacement for tr in a pipeline).
to_upper () {
    for word in "$@" ; do
        echo "${word^^}"
    done
}

# Convert one or more words to lowercase without explicit variable substition.
# (Not meant as a replacement for tr in a pipeline).
to_lower () {
    for word in "$@" ; do
        echo "${word,,}"
    done
}

# Evaluates if argument2 is present as distinct word in argument1.
# Equivalent of grep -w.
# TODO(nicolaw): Should this be extended to have is_word_in_strings, and/or
#                is/are_words_in_string variants? Would that be overkill?
is_word_in_string () {
    declare str="${1:-}"
    declare re="\\b${2:-}\\b"
    [[ "$str" =~ $re ]] && return 0
    return 1
}

# Append a list of word(s) to argument1 if they are not already present as
# distinct words.
append_if_not_present () {
    declare base_str="${1:-}"; shift
    for add_str in "$@" ; do
        if ! matches_word "$base_str" "$add_str" ; then
            base_str="${base_str} ${add_str}"
        fi
    done
    echo "${base_str## }"
}

# Returns all mount points, optionally filtered by device.
get_fs_mounts () {
    declare device
    [[ -z "${1:-}" ]] || device=$(readlink -f "${1}")
    while IFS=" " read -r source target rest; do
        # Need echo -e to unescape source/target.
        if [[ -z "${device:-}" || "$(echo -e "${source}")" = "${device}" ]] ; then
            echo -e "${target}"
        fi
    done < /proc/mounts
}

# %w %W  time of file birth; - or 0 if unknown (creation)
# %x %X  time of last access, human-readable (read)
# %y %Y  time of last modification, human-readable (content)
# %z %Z  time of last change, human-readable (meta data)
get_file_age () {
    echo -n $(( $(get_unixtime -1) - $($BLIP_EXTERNAL_CMD_STAT -c %Y "${1:-}") ))
}

# Define ANSI colour code variables.
# https://en.wikipedia.org/wiki/ANSI_escape_code
if is_true "${BLIP_ANSI_VARIABLES:-}" && [[ -z "${ANSI[@]+defined}" ]] ; then
    declare -rx ANSI_RESET="[0m"          #

    declare -rx ANSI_BLINK_SLOW="[5m"     #
    declare -rx ANSI_BLINK_FAST="[6m"     #
    declare -rx ANSI_BLINK_OFF="[25m"     #

    declare -rx ANSI_HIDDEN_ON="[8m"      #
    declare -rx ANSI_HIDDEN_OFF="[28m"    #

    declare -rx ANSI_STRIKE_ON="[9m"      #
    declare -rx ANSI_STRIKE_OFF="[29m"    #
    declare -rx ANSI_ITALIC_ON="[3m"      #
    declare -rx ANSI_ITALIC_OFF="[23m"    #

    declare -rx ANSI_UNDERLINE_ON="[4m"   #
    declare -rx ANSI_UNDERLINE_OFF="[24m" #
    declare -rx ANSI_OVERLINE_ON="[53m"   #
    declare -rx ANSI_OVERLINE_OFF="[55m"  #

    declare -rx ANSI_FRAME_ON="[51m"      #
    declare -rx ANSI_FRAME_OFF="[54m"     #
    declare -rx ANSI_ENCIRCLE_ON="[52m"   #
    declare -rx ANSI_ENCIRCLE_OFF="[54m"  #

    declare -rx ANSI_BOLD_ON="[1m"        #
    declare -rx ANSI_BOLD_OFF="[22m"      #
    declare -rx ANSI_FAINT_ON="[2m"       #
    declare -rx ANSI_FAINT_OFF="[22m"     #

    declare -rx ANSI_INVERSE_ON="[7m"     #
    declare -rx ANSI_INVERSE_OFF="[27m"   #

    declare -rx ANSI_FG_BLACK="[30m"      #
    declare -rx ANSI_FG_RED="[31m"        #
    declare -rx ANSI_FG_GREEN="[32m"      #
    declare -rx ANSI_FG_YELLOW="[33m"     #
    declare -rx ANSI_FG_BLUE="[34m"       #
    declare -rx ANSI_FG_MAGENTA="[35m"    #
    declare -rx ANSI_FG_CYAN="[36m"       #
    declare -rx ANSI_FG_WHITE="[37m"      #
    declare -rx ANSI_FG_DEFAULT="[39m"    #

    declare -rx ANSI_BG_BLACK="[40m"      #
    declare -rx ANSI_BG_RED="[41m"        #
    declare -rx ANSI_BG_GREEN="[42m"      #
    declare -rx ANSI_BG_YELLOW="[43m"     #
    declare -rx ANSI_BG_BLUE="[44m"       #
    declare -rx ANSI_BG_MAGENTA="[45m"    #
    declare -rx ANSI_BG_CYAN="[46m"       #
    declare -rx ANSI_BG_WHITE="[47m"      #
    declare -rx ANSI_BG_DEFAULT="[49m"    #

    declare -rxA ANSI=(
        [reset]="$ANSI_RESET"
        [blink]="$ANSI_BLINK_SLOW"
        [blink_slow]="$ANSI_BLINK_SLOW"
        [blink_fast]="$ANSI_BLINK_FAST"
        [blink_slow_on]="$ANSI_BLINK_SLOW"
        [blink_fast_on]="$ANSI_BLINK_FAST"
        [blink_off]="$ANSI_BLINK_OFF"
        [hidden]="$ANSI_HIDDEN_ON"
        [hidden_on]="$ANSI_HIDDEN_ON"
        [hidden_off]="$ANSI_HIDDEN_OFF"
        [strike]="$ANSI_STRIKE_ON"
        [strike_on]="$ANSI_STRIKE_ON"
        [strike_off]="$ANSI_STRIKE_OFF"
        [italic]="$ANSI_ITALIC_ON"
        [italic_on]="$ANSI_ITALIC_ON"
        [italic_off]="$ANSI_ITALIC_OFF"
        [underline]="$ANSI_UNDERLINE_ON"
        [underline_on]="$ANSI_UNDERLINE_ON"
        [underline_off]="$ANSI_UNDERLINE_OFF"
        [overline]="$ANSI_OVERLINE_ON"
        [overline_on]="$ANSI_OVERLINE_ON"
        [overline_off]="$ANSI_OVERLINE_OFF"
        [frame]="$ANSI_FRAME_ON"
        [frame_on]="$ANSI_FRAME_ON"
        [frame_off]="$ANSI_FRAME_OFF"
        [encircle]="$ANSI_ENCIRCLE_ON"
        [encircle_on]="$ANSI_ENCIRCLE_ON"
        [encircle_off]="$ANSI_ENCIRCLE_OFF"
        [bold]="$ANSI_BOLD_ON"
        [bold_on]="$ANSI_BOLD_ON"
        [bold_off]="$ANSI_BOLD_OFF"
        [faint]="$ANSI_FAINT_ON"
        [faint_on]="$ANSI_FAINT_ON"
        [faint_off]="$ANSI_FAINT_OFF"
        [inverse]="$ANSI_INVERSE_ON"
        [inverse_on]="$ANSI_INVERSE_ON"
        [inverse_off]="$ANSI_INVERSE_OFF"
        [black]="$ANSI_FG_BLACK"
        [fg_black]="$ANSI_FG_BLACK"
        [bg_black]="$ANSI_BG_BLACK"
        [red]="$ANSI_FG_RED"
        [fg_red]="$ANSI_FG_RED"
        [bg_red]="$ANSI_BG_RED"
        [green]="$ANSI_FG_GREEN"
        [fg_green]="$ANSI_FG_GREEN"
        [bg_green]="$ANSI_BG_GREEN"
        [yellow]="$ANSI_FG_YELLOW"
        [fg_yellow]="$ANSI_FG_YELLOW"
        [bg_yellow]="$ANSI_BG_YELLOW"
        [blue]="$ANSI_FG_BLUE"
        [fg_blue]="$ANSI_FG_BLUE"
        [bg_blue]="$ANSI_BG_BLUE"
        [magenta]="$ANSI_FG_MAGENTA"
        [fg_magenta]="$ANSI_FG_MAGENTA"
        [bg_magenta]="$ANSI_BG_MAGENTA"
        [cyan]="$ANSI_FG_CYAN"
        [fg_cyan]="$ANSI_FG_CYAN"
        [bg_cyan]="$ANSI_BG_CYAN"
        [white]="$ANSI_FG_WHITE"
        [fg_white]="$ANSI_FG_WHITE"
        [bg_white]="$ANSI_BG_WHITE"
        [fg_default]="$ANSI_FG_DEFAULT"
        [bg_default]="$ANSI_BG_DEFAULT"
        )
fi

#
# That strange feeling you're experiencing right now... I should apologise for
# that. It's called cognitive dissonance.
# https://en.wikipedia.org/wiki/Cognitive_dissonance
#
# Sorry if you consider yourself harmed as a result of reading or using this
# software. If it makes any difference to you, I now have very puffy eyes from
# writing this.
#
# "...Hello Doctor, I've been having trouble with my eyes. They're swollen..."
# 

