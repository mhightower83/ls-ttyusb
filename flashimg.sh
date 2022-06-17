#!/bin/bash
#
#   Copyright 2021 M Hightower
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
# flashimg.sh
#
#

# default fash device to use
flash_dev="/dev/mmcblk1"

namesh="${0##*/}"

printShortUsage() {
  cat <<EOF
Usage:

  $namesh
  $namesh rasbian.img [flash device name]
  $namesh --help

  Example:
    $namesh rasbian.img /dev/mmcblk1

EOF
  return 0
}

printUsage() {
  # local namesh=`basename $0`
  cat <<EOF

This bash script can be dangerous. It writes an image file to a block
device. If you are not careful, you can destroy all your data. Exercise
extreme caution!


Usage:

  $namesh
  $namesh rasbian.img [flash device name]
  $namesh --help

  Supported operations:

    $namesh
      Shows a list of Drives. The /dev/sd... device name, size of the device
      (which might be a partition) and the device name description is reported
      for each. The list is filtered to remove mounted and ATA devices.


    $namesh rasbian.img
      Write a file named 'rasbian.img' to flash device '$flash_dev'


    $namesh [rasbian.img] [flash device name]
      Write file named rasbian.img to the flash device name specified.


    $namesh --help
      This usage message.

EOF
  return 0
}

flashFilter() {
  local devLink identifier sdValue
  local missing=1

  for devLink in /dev/disk/by-id/*; do
    if [[ "/dev/disk/by-id/*" == "${devLink}" ]]; then
      echo "No Disk devices found"
      echo "Specificly, /dev/disk/by-id/* shows no devices."
      return 1
    else
      # filter out wwn and ata drives
      identifier="${devLink#/dev/disk/by-id/}"
      identifier="${identifier/#wwn-*/}"
      identifier="${identifier/#ata-*/}"
      if [[ -n ${identifier} ]]; then
        sdValue=$(readlink -n -f "${devLink}")
        if [[ -n ${sdValue} ]]; then
          if [[ ${#} -eq 0 ]]; then
            echo "${sdValue}"
            missing=0
          else
            if  [[ "${1}" == "${sdValue}" ]]; then
              echo "${sdValue}"
              return 0;   # exists
            fi
          fi
        fi
      fi
    fi
  done
  return ${missing}
}

# print a list of "disk" device names ie. /dev/...
# the raw drive device not the partition device name
getdiskdev() {
  local rc rc2
  { hwinfo --disk --short; rc=$?; } 2>/dev/null | tail -n +2  | awk '{print $1}'
  rc2=$?
  if [[ 0 -ne $rc ]]; then
    return $rc
  fi
  return $rc2
}

# Validate that the a device exist and is not mounted
# w/o argument shows a list of drives available
showIdleFlashDrv() {
  local rc failed disk_list fetch_list available_list device nmatch
  failed=1  # 0 => success, 1 => failed
  fetch_list=""
  # Get list if device names for Disks drives
  disk_list=$( getdiskdev ) # this command is slow, cache/keep results
  rc=$?
  if [[ 0 -ne $rc ]]; then
    echo -e "\nError getting list of disk drives.\n"
    return 2
  fi

  if [[ -z "${disk_list}" ]]; then
    echo -e "\nThe list of disk drives came up empty.\n"
    return 3
  fi

  # Remove drives that don't appear in flash filter
  filter_list=$( echo "${disk_list}" | grep -f <( flashFilter ) )

  # Now filter out mounted drives
  for device in ${filter_list}; do
    if [[ 0 -eq ${#} ]] || [[ "${1}" == "${device}" ]]; then
      nmatch=$(findmnt | grep "${device}" | wc | awk '{print $1}')
      rc=$?

      if [[ 0 -eq $rc ]]; then            # do this on success
        if [[ 0 -eq ${nmatch}  ]]; then   # 0 if not mounted
          if [[ ${#} -eq 0 ]]; then       # no argument, report available drives
            failed=0
            fetch_list="${fetch_list}${device}\n"
          elif [[ "${1}" == "${device}" ]]; then
            if [[ 0 -eq $? ]]; then
              fetch_list="${device}\n"
              failed=0
            else
              failed=4                    # drive not connected / available
            fi
          fi
        else
          if [[ ${#} -ne 0 ]] && [[ "${1}" == "${device}" ]]; then
            failed=5                      # drive mounted
          fi
        fi
      fi
    fi
  done

  # Evaluate the results and try to be helpful
  if [[ ${#} -ne 0 ]]; then
    if [[ 0 -eq $failed ]]; then
      if [[ -n ${fetch_list} ]]; then
        echo -e "Target drive selected for flashing:\n"
        lsblk -f $( echo -e "${fetch_list}" | grep -f <( flashFilter ) )
      else
        echo -e "\n\nInternal Error, Target drive selected for flashing is empty. ??\n\n"
        exit 1000
      fi
    elif [[ 1 -eq $failed ]]; then
      echo -e "The selected drive, \"${1}\", was not found."
      echo -e "To flash a drive it must be connected and unmounted."
      echo -e "\nAlso when using the file GUI, be sure you use unmount and not eject on the drive.\n"
    elif [[ 4 -eq $failed ]]; then
      echo -e "The selected drive, \"${1}\", is not connected."
      echo -e "To flash a drive it must be connected and unmounted."
      echo -e "\nAlso when using the file GUI, be sure you use unmount and not eject on the drive.\n"
    elif [[ 5 -eq $failed ]]; then
      echo -e "The selected drive, \"${1}\", is not available. It is currently mounted. "
      echo -e "To flash a drive it must be connected and unmounted."
      echo -e "\nAlso when using the file GUI, be sure you use unmount and not eject on the drive.\n"
    fi
    return ${failed}
  fi

  available_list=""
  if [[ 1 -eq $failed ]]; then
    echo -e "\nAll drives are mounted. To flash a drive it must not be mounted."
    echo -e "Make sure you plugged in your flash drive."
    echo -e "Then, check this list for your flash drive and unmount:\n"
    available_list="${disk_list}"
  else
    echo -e "\nThese are the drives currently available:\n"
    available_list="${fetch_list}"
  fi
  if [[ -n ${available_list} ]]; then
    available_list=$( echo -e "${available_list}" | grep -f <( flashFilter ) )
  fi
  if [[ -n ${available_list} ]]; then
    lsblk -f ${available_list}
  else
    echo -e "  <none>"
  fi
  echo -e "\nIf you do not see the drive you want to use, make sure it is not mounted."
  echo -e "\nAlso when using the file GUI, be sure you use unmount and not eject on the drive.\n"
  return $failed
}

processFlashWriteDialog() {
  echo ""
  showIdleFlashDrv "${flash_dev}"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    exit $rc
  fi

  echo -e "\nThis command line will be used:" >&2
  echo -e "  sudo dd if=${src} of=${flash_dev} bs=4M conv=fsync status=progress" >&2
  echo -e "\nIf you continue, all data currently on \"${flash_dev}\" will be lost!" >&2
  echo -e -n "\nWould you like to continue (yes/no)? " >&2
  unset yesno
  gotit=-1
  for (( i=12; (i>0)&&(${gotit}<0); i-=1 )); do
    read yesno
    case "${yesno,,}" in
      yes) gotit=1;
           ;;
      no)  gotit=0;
           ;;
      *)   echo -n "Please type 'yes' or 'no': " >&2
           ;;
    esac
  done
  if [[ $gotit -lt 1 ]]; then
    echo "aborted" >&2
    echo ""
    return 100
  fi

  echo ""
  echo "sudo dd if=${src} of=${flash_dev} bs=4M conv=fsync status=progress"
  echo ""
  # For development puposes the sudo line below is commented out
  # it should be uncommented for release and final testing
  # sudo dd if=${src} of=${flash_dev} bs=4M conv=fsync status=progress

}

# Main: Start processing command line
#
if [[ "${1}" == "--help" ]] || [[ ${#} -gt 2 ]]; then
  printUsage
  exit $?

elif [[ ${#} -eq 0 ]]; then
  showIdleFlashDrv
  exit $?
fi

if [[ ${#} -eq 2 ]]; then
  flash_dev=${2}
fi
src=${1}

if [[ -z "${flash_dev}" ]]; then
  echo -e "\nInternal script error: shell variable flash_dev was not set\n"
  printShortUsage
  exit 11

fi

# Fixup driver name if they forgot the /dev/...
# I am a little reluctant in doing this; however, since they must confirm the
# results before flashing occurs. It should be okay.
flash_dev_alt="${flash_dev##/*/}"
if [[ "${flash_dev_alt}" == "${flash_dev}" ]]; then
  flash_dev="/dev/${flash_dev}"
fi

if ! [[ -b "${flash_dev}" ]]; then
  echo -e "\nTarget drive, \"${flash_dev}\", was not found\n"
  printShortUsage
  exit 12

else
  if [[ -s ${src} ]]; then
    processFlashWriteDialog
    exit $?
  else
    echo "Disk image file \"${src}\" does not exist or is empty."
    printShortUsage
    exit 13
  fi
fi

exit 102

# references:
# https://unix.stackexchange.com/questions/52215/determine-the-size-of-a-block-device
# https://superuser.com/questions/763150/how-can-i-know-if-a-partition-is-mounted-or-unmounted
# https://unix.stackexchange.com/a/431968
# https://www.linuxjournal.com/article/2156  - Introduction to Named Pipes
