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
# grep-less.sh
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

unset ignore_case
if [[ "-" == "${1:0:1}" ]]; then
  if [[ "-i" == "${1:0:2}" ]]; then
    ignore_case="-i"
  fi
  grep_pattern="${2}"
else
  grep_pattern="${1}"
fi
[[ -n "$ignore_case" && -n "$grep_pattern" ]] && grep_pattern="${grep_pattern,,}"

function print_help() {
  cat <<EOF
Recursive search for files with matching patterns. Use dialog to present
resulting lines containing matches. Multiple lines for a file will appear when
multiple matches in a file are found. From the top menu you can selected
view/diff/edit. $namesh and ${namesh:1} are very simalar.

$namesh pattern [ [-iv] pattern2 ] [ [-iv] pattern3 ]
EOF
}

declare -a filehistory
function add2filehistory() {
  filehistory[${#filehistory[@]}]="$1"
}

function statusfile() {
  sha1sum "$1" | sed 's: .*/:  :' | tr "\n" " "
  stat --print=" %.19y %8s %h  %N\n" "${1}"
}
export -f statusfile

grep_tree() {
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
  search_tree_output=$(mktemp)
  search_tree_output_in=$(mktemp)
  unset options
  if [[ "-" == "${1:0:1}" ]]; then
    options="${1:1}"
    shift
  fi
  if [[ -z "${1}" ]]; then
    return
  fi
  grep -rRnIT${options} -Dskip "${1}" 2>/dev/null >${search_tree_output}
  shift
  while [ -n "${1}" ]; do
    mv ${search_tree_output} ${search_tree_output_in}
    if [[ "-" == "${1:0:1}" ]]; then
      if [[ -n "${2}" ]]; then
        grep ${1} "${2}" <${search_tree_output_in} 2>/dev/null >${search_tree_output}
        shift
      else
        mv ${search_tree_output_in} ${search_tree_output}
        echo "${0}:1: stray command line option \"${1}\" without pattern" >>${search_tree_output}
      fi
    else
      grep "${1}" <${search_tree_output_in} 2>/dev/null >${search_tree_output}
    fi
    shift
  done
  [ -f $search_tree_output ] && cat ${search_tree_output}
  [ -f $search_tree_output ] && rm $search_tree_output
  [ -f ${search_tree_output_in} ] && rm ${search_tree_output_in}
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
    --column-separator "|-|-|-|" \
    --title "Recursive Grep Results" \
    --default-item $menu_item \
    --menu "Primary search pattern, \"${grep_pattern}\", results. Pick a file to view:" 0 0 0 \
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
  echo "You selected: $entry"
  jumpto=$( echo "$entry" | cut -d':' -f2 | xargs )
  file=$( echo "$entry" | cut -d':' -f1 )
  file=$( realpath "$file" )

  if [[ $rc == $DIALOG_OK ]]; then
    # echo -n "$file" | xclip -selection clipboard
    add2filehistory "$file"
    less +$jumpto -N -p"${grep_pattern}" $ignore_case "$file"
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
  grep_tree "$@" |
    sed '/^.git/d' |
    sed 's/\t/|-|-|-|/' |
    sed 's/\\/\\\\/g' |
    sed 's/"/\\"/g' >$command_output
  if [[ -s $command_output ]]; then
    #build a dialog configuration file
    cat $command_output |
      awk '{print NR " \"" $0 "\""}' |
      tr "\n" " " >$menu_config
  else
    return 1
  fi
  return 0
}

################################################################################
# main - grep-less.sh
#

# From https://unix.stackexchange.com/a/70868

#make some temporary files
command_output=$(mktemp)
menu_config=$(mktemp)
menu_output=$(mktemp)
lastfile=""
menu_item=1

#make sure the temporary files are removed even in case of interruption
trap "rm $command_output;
      rm $menu_output;
      rm $menu_config;" SIGHUP SIGINT SIGTERM

if [[ -z "${1}" || "--help" == "${1}" ]]; then
  print_help
  exit 255
fi

if make_menu "$@"; then
  while :; do
    do_again
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
  echo "  grep_pattern: \"${grep_pattern}\""
  printf '  %s\n' "${filehistory[@]}"
else
  echo "Empty search results for:"
  echo "  $namesh "${cmd_args[@]}
fi

#clean the temporary files
[ -f $command_output ] && rm $command_output
[ -f $menu_output ] && rm $menu_output
[ -f $menu_config ] && rm $menu_config
