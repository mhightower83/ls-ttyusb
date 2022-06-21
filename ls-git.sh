#!/bin/bash
# set config file
DIALOGRC=/home/mhightow/.dialogrc.dark
if [[ ! -s "$DIALOGRC" ]]; then
  unset DIALOGRC
fi

namesh="${0##*/}"

function print_help() {
  cat <<EOF
Show available branches to checkout, edit description, or show log

$namesh
EOF
}

declare -a branchhistory
function add2branchhistory() {
  branchhistory[${#branchhistory[@]}]="$1"
}

function editBranchDesc() {
  git branch ${1} --edit-description
}

function listBranchWithDesc() {
  branches=`git branch --list --sort=-committerdate $1`
  rc=$?
  if [[ $rc != 0 ]]; then
    return $rc
  fi

  # requires git > v.1.7.9

  # you can set branch's description using command
  # git branch --edit-description
  # this opens the configured text editor, enter message, save and exit
  # if one editor does not work (for example Sublime does not work for me)
  # try another one, like vi

  # you can see branch's description using
  # git config branch.<branch name>.description

  while read -r branch; do
    # git marks current branch with "* ", remove it
    clean_branch_name=${branch//\*\ /}
    # replace colors
    clean_branch_name=`echo $clean_branch_name | tr -d '[:cntrl:]' | sed -E "s/\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g"`
    # replace symbolic-ref like `HEAD -> master`
    clean_branch_name=`echo $clean_branch_name | sed -E "s/^.+ -> //g"`

    description=`git config branch.$clean_branch_name.description`
    if [ "${branch::1}" == "*" ]; then
      printf "$branch | $description\n"
    else
      printf "  $branch | $description\n"
    fi
  done <<< "$branches"
  return 0

  # example output
  # $ ./branches.sh
  # * master        this is master branch
  # one             this is simple branch for testing
}

function do_again() {
  #launch the dialog, get the output in the menu_output file
  # --no-cancel

  # Duplicate (make a backup copy of) file descriptor 1
  # on descriptor 3
  exec 3>&1

  # catch the output value
  menu_item=$(dialog \
    --no-collapse \
    --clear \
    --extra-label "Edit Description" \
    --extra-button \
    --help-label "View Log" \
    --help-button \
    --cancel-label "Exit, No Change" \
    --ok-label "Checkout Branch" \
    --column-separator "|" \
    --title "git branches available" \
    --default-item $menu_item \
    --menu "Pick a branch and select an action" 0 0 0 \
    --file $menu_config 2>&1 1>&3)

  rc=$?

  # Close file descriptor 3
  exec 3>&-

  echo "$menu_item"
  # clear
  if [[ $rc == 0 ]]; then
    # the Yes or OK button.
    # we use this for view/less
    :
  elif [[ $rc == 2 ]]; then
    # --help-button was pressed.
    # Repurpose for view log, skip "HELP " to get to the menu number
    menu_item=${menu_item#* }
  elif [[ $rc == 3 ]]; then
    # --extra-button was pressed.
    # We use this for edit
    :
  else
    # Exit/No/Cancel, ESC and everything else
    return $rc
  fi

  #recover the associated line in the output of the command
  # Format "* branch/tdescription"
  # entry=$(cut -c 3- $command_output | sed -n "${menu_item}p" $config_file)
  entry=$(cut -c 3- $command_output | sed -n "${menu_item}p")

  #replace echo with whatever you want to process the chosen entry
  echo "You selected: $entry"
  branch=$( echo "$entry" | cut -d' ' -f1 )

  if [[ $rc == 0 ]]; then
    echo "branch: $branch"
    if [[ -n $branch ]]; then
      add2branchhistory "$branch"
      git checkout $branch >$giterrorlog 2>&1
      lastbranch=$branch
    fi
  elif [[ $rc == 2 ]]; then
    echo "log branch: $branch"
    if [[ -n $branch ]]; then
      clear
      add2branchhistory "$branch"
      git log --name-only $branch
      lastbranch=$branch
    fi
  elif [[ $rc == 3 ]]; then
    add2branchhistory "$branch"
    editBranchDesc $branch
    lastbranch=$branch
  fi
  return $rc
}

function refresh() {
  #replace ls with what you want
  listBranchWithDesc "--no-color" | sed 's/ *$//g' >$command_output
  rc=$?
  if [[ $rc != 0 ]]; then
    echo "listBranchWithDesc return code $rc"
    exit 1
  fi

  # cat $command_output
  # exit 0

  #build a dialog configuration file
  cat $command_output |
    awk '{print NR " \"" $0 "\""}' |
    tr "\n" " " >$menu_config
}

# From https://unix.stackexchange.com/a/70868

#make some temporary files
command_output=$(mktemp)
menu_config=$(mktemp)
menu_output=$(mktemp)
giterrorlog=$(mktemp)
lastbranch=""
menu_item=1

#make sure the temporary files are removed even in case of interruption
trap "rm $command_output;
      rm $menu_output;
      rm $menu_config;
      rm $giterrorlog;" SIGHUP SIGINT SIGTERM

if refresh; then
  while :; do
    do_again
    rc=$?
    if [[ $rc == 0 ]]; then   # OK
      # done
      clear
      break
    elif [[ $rc == 1 ]]; then   # Cancel
      clear
      break
    elif [[ $rc == 2 ]]; then   # Help
      :
    elif [[ $rc == 3 ]]; then   # Extra
      # echo "Carry on"
      refresh
    else
      clear
      break
    fi
  done
  echo "$namesh ""$@"
  printf '  %s\n' "${branchhistory[@]}"
  cat $giterrorlog

else
  echo "Not a git project:"
  pwd
fi

#clean the temporary files
[ -f $command_output ] && rm $command_output
[ -f $menu_output ] && rm $menu_output
[ -f $menu_config ] && rm $menu_config
[ -f $giterrorlog ] && rm $giterrorlog



  # clear
  # if [[ $rc != 0 ]]; then
  #   if [[ $rc == 0 ]]; then
  #     echo "0 - if dialog is exited by pressing the Yes or OK button."
  #   elif [[ $rc == 1 ]]; then
  #     echo "1 - if the No or Cancel button is pressed."
  #   elif [[ $rc == 2 ]]; then
  #     echo "2 - if the Help button is pressed."
  #   elif [[ $rc == 3 ]]; then
  #     echo "3 - if the Extra button is pressed."
  #   elif [[ $rc == -11 ]]; then
  #     echo "-1 - if errors occur inside dialog or dialog is exited by pressing the ESC key."
  #   else
  #     echo "unknown exit: ${rc}"
  #   fi
  #   exit $rc
  # fi
