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
# find-less.sh
#
# WIP

# set config file
DIALOGRC=$( realpath ~/.dialogrc.dark )
if [[ ! -s "$DIALOGRC" ]]; then
  unset DIALOGRC
fi

namesh="${0##*/}"
cmd_args=("$@")

function print_help() {
  cat <<EOF
Find matching files. Use dialog to present results with sha1 hash and details.
From the menu you can view/diff/edit.

$namesh [-i] file-name [file-name2 [file-name3] ...]
  -i for case insensitive
  use '' to hold wild card names


Prompt to paste a list if files to search for lines are expected to contain
the "#include" string.

$namesh

EOF
}

declare -a filehistory
function add2filehistory() {
  filehistory[${#filehistory[@]}]="$1"
}

function statusfile3() {
  sha1sum "$1" | sed 's: .*/:  :' | tr "\n" " "
  stat --print=" %.19y %8s %h  %N\n" "${1}"
}

function statusfile() {
  # sha1sum "$1" | cut -d' '   -f1 | tr "\n" "\t"
  # sha1sum "$1" | sed 's: .*/:  :' | tr "\n" " "
  declare -a list=( $( sha1sum "$1" | sed 's: .*/: :' | tr "\n" " " ) )
  printf "%s %${maxwidth}s  " "${list[@]}"
  stat --print="%.19y %8s %h  %N\n" "${1}"
  # stat --print="%.19y %8s %h\t" "${1}"
  # echo -n "${1}" | sed 's:.*/::'
  # stat --print="  %N\n" "${1}"
}
export -f statusfile

function search_tree2() {
  # find -L . -xdev -type f ${1} "${2}" 2>/dev/null
  # https://stackoverflow.com/a/7972481
  find . -xdev -type f ${1} "${2}" 2>/dev/null
  if [[ -n "${3}" ]]; then
    if [[ -n "${1}" ]]; then
      icase=${1}
    else
      icase=""
    fi
    shift
    shift
    while [ -n "${1}" ]; do
      find .  -xdev -type f $icase "${1}" 2>/dev/null
      shift
    done
  fi
}

function search_tree() {
  # find -L . -xdev -type f ${1} "${2}" 2>/dev/null
  if [[ -n "${1}" ]]; then
    icase=${1}
    shift
    while [ -n "${1}" ]; do
      # https://stackoverflow.com/a/7972481
      find .  -xdev -type f $icase "${1}" 2>/dev/null
      shift
    done
  fi
}

function do_again() {
  #launch the dialog, get the output in the menu_output file
  # --no-cancel
  dialog \
    --no-collapse \
    --clear \
    --extra-label "Diff Previous" \
    --extra-button \
    --help-label "Edit" \
    --help-button \
    --cancel-label "Exit" \
    --ok-label "View" \
    --column-separator "\t" \
    --title "Find File Results" \
    --default-item $menu_item \
    --menu "Pick a file to view" 0 0 0 \
    --file $menu_config 2>$menu_output
  rc=$?

  # recover the output value
  menu_item=$(<$menu_output)
  echo "$menu_item"

  if [[ $rc == 0 ]]; then
    # the Yes or OK button.
    # we use this for view/less
    :
  elif [[ $rc == 1 ]]; then
    # The No or Cancel button was pressed."
    return $rc
  elif [[ $rc == 2 ]]; then
    # --help-button was pressed.
    # Repurpose for edit, skip "HELP " to get to the menu number
    menu_item=${menu_item#* }
  elif [[ $rc == 3 ]]; then
    # --extra-button was pressed.
    # We use this for diff
    :
  elif [[ $rc == -1 ]]; then
    # echo "-1 - if errors occur inside dialog or dialog is exited by pressing the ESC key."
    return 1
  elif [[ $rc == 255 ]]; then
    # echo "255 - if errors occur inside dialog or dialog is exited by pressing the ESC key."
    return 1
  else
    echo "unknown exit: ${rc}"
    return $rc
  fi

  # recover the associated line in the output of the command
  # Format "* branch/tdescription"
  # entry=$(cut -c 1- $command_output | sed -n "${menu_item}p" $config_file)
  entry=$(sed -n "${menu_item}p" $command_output)

  #replace echo with whatever you want to process the chosen entry
  echo "You selected: $entry"
  jumpto=1
  file=$( echo "$entry" | cut -d\' -f2 )
  file=$( realpath "$file" )

  if [[ $rc == 0 ]]; then
    # echo -n "$file" | xclip -selection clipboard
    add2filehistory "$file"
    less +$jumpto -N "$file"
    lastfile="$file"
    # echo "less +$jumpto \"$file\""
  elif [[ $rc == 3 ]]; then
    if [[ -n "${lastfile}" ]]; then
      add2filehistory "$file"
      diff -w "${lastfile}" "${file}" | less
    fi
    lastfile="${file}"
  elif [[ $rc == 2 ]]; then
    add2filehistory "$file"
    gedit "$file" +$jumpto
    lastfile="$file"
  fi
  return $rc
}

function make_menu2() {
  if [[ "-i" == "${1}" ]]; then
    namecase="-iname"
    shift
  else
    namecase="-name"
  fi
  search_tree "${namecase}" "$@" |
    sed '/^.\/.git/d' |
    sed 's/"/\\"/g' |
    xargs -I {} bash -c 'statusfile "$@"' _ {} |
    sort |
    cut -c 34- >$command_output
    cat $command_output
  if [[ -s $command_output ]]; then
    # build a dialog menu configuration file
    cat $command_output |
      awk '{print NR " \"" $0 "\""}' |
      tr "\n" " " >$menu_config
  else
    return 1
  fi
  return 0
}
function make_menu() {
  if [[ "-i" == "${1}" ]]; then
    namecase="-iname"
    shift
  else
    namecase="-name"
  fi
  search_tree "${namecase}" "$@" |
    sed '/^.\/.git/d' |
    sed 's/"/\\"/g' >$command_output
  if [[ -s $command_output ]]; then
    mv $command_output $temp_io
    # build a dialog menu configuration file
    maxwidth=$( sed 's:.*/: :' $temp_io | wc -L | cut -d' ' -f1 )
    export maxwidth
    cat $temp_io |
      xargs -I {} bash -c 'statusfile "$@"' _ {} |
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
# main - find-less.sh
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

#make sure the temporary files are removed even in case of interruption
trap "rm $command_output;
      rm $menu_output;
      rm $temp_io;
      rm $menu_config;" SIGHUP SIGINT SIGTERM

if [[ "--help" == "${1}" ]]; then
  print_help
  exit 255
elif [[ -z "${1}" ]]; then
  clear
  echo "Paste below a list of the files to search for."
  echo "Terminate the list with an <CTRL-D> on an empty line."
  echo ""
  cat >$temp_io
  if [[ $? != 0 ]]; then
    echo "No input"
    exit 255
  fi
  # readarray -t cmd_args < <(
  #   cat  $temp_io |
  #   sed 's/.*<//;s/>*$//;s/[^"]*"//;s/"*$//;s:.*/::' )
  readarray -t cmd_args < <(
    sed 's/#[[:blank:]]*include/#include/' $temp_io |
    grep '#include' |
    sed 's/^.*include//;s/.*<//;s/>*$//;s/[^"]*"//;s/"*$//;s:.*/::' )
  # readarray -t cmd_args < <(
  #   sed 's/#[[:blank:]]*include/#include/' $temp_io |
  #   grep '#include' |
  #   sed 's/^.*include//' |
  #   sed 's/.*<//' |
  #   sed 's/>*$//' |
  #   sed 's/[^"]*"//' |
  #   sed 's/"*$//' |
  #   sed 's:.*/::' )
  # declare -p cmd_args
fi

if make_menu "${cmd_args[@]}"; then
  while :; do
    do_again "${1}"
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
    else
      clear
      echo "Error: $rc"
      cat $menu_output
      break
    fi
  done
  echo "$namesh "${cmd_args[@]}
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
