#!/bin/bash
#
#   Copyright 2022 M Hightower
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# grep-less2.sh
#
# WIP

# Define the dialog exit status codes
: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

# EDITER='gedit +$jumpto "${file}"'
EDITER='atom -a "${file}:${jumpto}"'

# set config file
DIALOGRC=$( realpath ~/.dialogrc.dark )
if [[ ! -s "$DIALOGRC" ]]; then
  unset DIALOGRC
fi

namesh="${0##*/}"
cmd_args="$@"


function print_help() {
  cat <<EOF
Recursive search for files with matching patterns. Uses "dialog" to present each
file with sha1 hash and other details. Contents of the file are not shown on the
top menu. From the top menu, you can select view/diff/edit. $namesh and
m${namesh} are very similar.

$namesh [-iv] pattern [ [-iv] pattern2 ] [ [-iv] pattern3 ]

-i    ignore case
-v    find files not containing the pattern

Additional options after -i or -iv will pass through to grep.
Unknown which additional options would be helpful.

EOF
}

declare -a filehistory
function add2filehistory() {
  filehistory[${#filehistory[@]}]="$1"
}

function statusfile() {
  list=$( sha1sum "$1" )
  SHA1="${list%% *}"
  FILE_NAME="${list#* }"
  FILE_NAME="${FILE_NAME#\*}"
  FILE_NAME="${FILE_NAME# }"
  FILE_NAME="${FILE_NAME##*/}"
  printf "%s %${maxwidth}s  " "$SHA1" "$FILE_NAME"
  stat --print="%.19y %8s %h  %N\n" "${1}"
}
export -f statusfile

function grep_tree() {
  local PATTERN search_tree_output ignore_case exclude_pattern options
  local search_tree_output_in

  # Must write directly a file to capture output not stdout.
  # This way we can set LESS_PATTERN for the caller. Cannot do this when
  # running from a separate shell. eg. var=$( function ) will not work.
  search_tree_output="$1"
  shift
  if [[ "--" == "${1:0:2}" ]]; then
    # experimental - escaping for grep needs to be removed search pattern not compatable with less etc.
    if hash rg 2>/dev/null; then
      rg --files-with-matches "${@}" 2>/dev/null
      return $?
    else
      rg --help
      return 1
    fi
  fi
  options=""
  if [[ "-" == "${1:0:1}" ]]; then
    options="${1:1}"
    shift
  fi
  if [[ -z "${1}" ]]; then
    return
  fi
  ignore_case=""
  exclude_pattern=""
  if [[ -n "${options}" ]]; then
    [[ "${options:0:1}" == "i" || "${options:1:1}" == "i" ]] && ignore_case="-i"
    [[ "${options:0:1}" == "v" || "${options:1:1}" == "v" ]] && exclude_pattern="-v"
  fi
  LESS_PATTERN=""
  if [[ -z "$exclude_pattern" ]]; then
    PATTERN="$1"
    if [[ -n "$ignore_case" ]]; then
      PATTERN="${PATTERN,,}"
      LESS_IGNORE_CASE="-i"
    fi
    LESS_PATTERN="${PATTERN}"
  fi
  grep -rRnIT${options} -Dskip "${1}" 2>/dev/null >${search_tree_output}
  shift

  search_tree_output_in=$(mktemp)
  while [ -n "${1}" ]; do
    mv ${search_tree_output} ${search_tree_output_in}
    options=""
    if [[ "-" == "${1:0:1}" ]]; then
      options="${1}"
      shift
    fi
    ignore_case=""
    exclude_pattern=""
    if [[ -n "${options}" ]]; then
      [[ "${options:1:1}" == "i" || "${options:2:1}" == "i" ]] && ignore_case="-i"
      [[ "${options:1:1}" == "v" || "${options:2:1}" == "v" ]] && exclude_pattern="-v"
    fi
    if [[ -z "$exclude_pattern" ]]; then
      PATTERN="$1"
      [[ -n "$ignore_case" ]] && PATTERN="${PATTERN,,}"
      if [[ -n "${LESS_PATTERN}" ]]; then
        LESS_PATTERN="${LESS_PATTERN}|${PATTERN}"
      else
        LESS_PATTERN="${PATTERN}"
      fi
    fi
    if [[ -n "${1}" ]]; then
      grep ${options} "${1}" <${search_tree_output_in} 2>/dev/null >${search_tree_output}
      shift
    else
      mv ${search_tree_output_in} ${search_tree_output}
      echo "${0}:1: stray command line option \"${1}\" without pattern" >>${search_tree_output}
    fi
  done
  [ -f ${search_tree_output_in} ] && rm ${search_tree_output_in}
}

function select_action() {
  exec 3>&1
  item=$(dialog \
    --no-items \
    --radiolist 'Select OK action' 10 25 5 \
    'less' 1 'off' \
    'diff' 2 'off' \
    'Edit' 3 'off' 2>&1 1>&3)

  rc=$?
  exec 3>&-

  echo "\"$item\""
  echo "\"$rc\""
  exit 0

  return $rc
}

function do_again() {
  [[ -z "${menu_item}" ]] && menu_item=1

  # Duplicate (make a backup copy of) file descriptor 1
  # on descriptor 3
  exec 3>&1

  # launch the dialog, get the output in the menu_output file
  # catch the output value
  menu_item=$(dialog \
    --no-collapse \
    --clear \
    --extra-label "Diff Previous" \
    --extra-button \
    --help-label "Edit" \
    --help-button \
    --cancel-label "Exit" \
    --ok-label "View" \
    --column-separator "\t" \
    --title "Recursive Grep Results" \
    --default-item $menu_item \
    --menu "Search results pick a file to view using less pattern, \"${LESS_PATTERN}\"." 0 0 0 \
    --file $menu_config 2>&1 1>&3)
    # --file $menu_config 2>$menu_output

  rc=$?

  # Close file descriptor 3
  exec 3>&-

  # recover the output value
  # menu_item=$(<$menu_output)
  echo "$menu_item"

  case $rc in
    $DIALOG_OK)
      # the Yes or OK button.
      # we use this for view/less
      ;;
    $DIALOG_HELP)
      # Repurpose for edit, skip "HELP " to get to the menu number
      menu_item=${menu_item#* } ;;
    $DIALOG_EXTRA)
      # We use this for diff
      ;;
    # $DIALOG_ITEM_HELP)    # Item-help button pressed.
    #   menu_item2=${menu_item2#* }
    #   return $rc ;;
    $DIALOG_CANCEL | $DIALOG_ESC)
      # process as cancel/Exit
      return 1 ;;
    * )
      # everything else
      return $rc ;;
  esac

  # recover the associated line in the output of the command
  # Format "* branch/tdescription"
  entry=$(sed -n "${menu_item}p" $command_output)

  #replace echo with whatever you want to process the chosen entry
  echo "You selected: '$entry'"
  jumpto=1
  file=$( echo "$entry" | cut -d\' -f2 )
  file=$( realpath "$file" )
  if [[ -f "${file}" && -n "${LESS_PATTERN}" ]]; then
    jumpto=$( grep $LESS_IGNORE_CASE -nm1 "${LESS_PATTERN%%|*}" "${file}" | cut -d\: -f1 )
  fi
  [[ -z "${jumpto}" ]] && echo "'$jumpto'=\$( grep $LESS_IGNORE_CASE -nm1 \"${LESS_PATTERN%%|*}\" \"${file}\" | cut -d\: -f1 )"

  if [[ $rc == $DIALOG_OK ]]; then
    # echo -n "$file" | xclip -selection clipboard
    add2filehistory "$file"
    LESS_PATTERN="${LESS_PATTERN/(/\\(}"
    LESS_PATTERN="${LESS_PATTERN/)/\\)}"
    less +$jumpto -N -p"${LESS_PATTERN}" $LESS_IGNORE_CASE "$file"
    lastfile="$file"
  elif [[ $rc == $DIALOG_EXTRA ]]; then
    if [[ -n "${lastfile}" ]]; then
      # echo -n "$file" | xclip -selection clipboard
      add2filehistory "$file"
      diff -w "${lastfile}" "${file}" | less
    fi
    lastfile="${file}"
  elif [[ $rc == $DIALOG_HELP ]]; then
    # echo -n "$file" | xclip -selection clipboard
    add2filehistory "$file"
    eval $EDITER
    # gedit +$jumpto "$file"
    # atom -a "${file}:${jumpto}"
    # less $menu_output
    lastfile="$file"
  fi
  return $rc
}

function make_menu() {
  search_tree_output=$(mktemp)
  grep_tree "$search_tree_output" "$@"
  cat $search_tree_output |
    cut -d':' -f1 | sort -u |
    sed '/^.git/d' |
    sed 's/"/\\"/g' >$command_output
  [ -f $search_tree_output ] && rm $search_tree_output

  if [[ -s $command_output ]]; then
    mv $command_output $temp_io
    # build a dialog menu configuration file
    maxwidth=$( sed 's:.*/: :' $temp_io | wc -L | cut -d' ' -f1 )
    export maxwidth
    cat $temp_io |
      xargs -I {} bash -c 'statusfile "$1"' _ {} |
      sort >$command_output
    cut -c 34- $command_output |
      awk '{print NR " \"" $0 "\""}' |
      tr "\n" " " >$menu_config
  else
    return 1
  fi
  return 0
}

################################################################################
# main - grep-less2.sh
#

# From https://unix.stackexchange.com/a/70868

#make some temporary files
command_output=$(mktemp)
menu_config=$(mktemp)
menu_output=$(mktemp)
temp_io=$(mktemp)
lastfile=""
menu_item=1
maxwidth=20
LESS_PATTERN=""
LESS_IGNORE_CASE=""

#make sure the temporary files are removed even in case of interruption
trap "rm $command_output;
      rm $menu_output;
      rm $temp_io;
      rm $menu_config;" SIGHUP SIGINT SIGTERM

if [[ -z "${1}" || "--help" == "${1}" ]]; then
  print_help
  exit 255
fi

if make_menu "$@"; then
  while :; do
    do_again "$@"
    rc=$?
    if [[ $rc == 0 ]]; then     # OK
      :
    elif [[ $rc == 1 ]]; then   # Cancel
      clear
      break
    elif [[ $rc == 2 ]]; then   # Help
      :
    elif [[ $rc == 3 ]]; then   # Extra
      :
    elif [[ $rc == 255 ]]; then   # ESC
      clear
      break
    else
      clear
      echo "Error: $rc"
      cat $menu_output
      break
    fi
  done
  echo "$namesh "${cmd_args[@]}
  echo "  less pattern: \"${LESS_PATTERN}\""
  printf '  %s\n' "${filehistory[@]}"
else
  echo "Empty search results for:"
  echo "  $namesh "${cmd_args[@]}
fi

#clean the temporary files
[ -f $command_output ] && rm $command_output
[ -f $menu_output ] && rm $menu_output
[ -f $menu_config ] && rm $menu_config
[ -f $temp_io ] && rm $temp_io
