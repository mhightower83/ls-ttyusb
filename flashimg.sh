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
      Write a file named 'rasbian.img' to flash device $flash_dev


    $namesh [rasbian.img] [flash device name]
      Write file named rasbian.img to the flash device name specified.


    $namesh --help
      This usage message.

EOF
  return 0
}

# This function will not report on ata and wwn drives
# This can help the effort to avoid overwriting a system HD
# note this is not a comprehensive solution for the issue.
findDrives() {
  local devLink devicename sdValue sizeis description printOnce
  local missing=1
  printOnce="Device|Size|Description"
  if [[ ${#} -ne 0 ]]; then
    unset printOnce
  fi
  for devLink in /dev/disk/by-id/*; do
    if [[ "/dev/disk/by-id/*" == "${devLink}" ]]; then
      echo "No Disk devices found"
      echo "Specificly, /dev/disk/by-id/* shows no devices."
      return 1
    else
      devicename="${devLink#/dev/disk/by-id/}"
      devicename="${devicename/#wwn-*/}"
      devicename="${devicename/#ata-*/}"
      sdValue=$(readlink -n -f "${devLink}")
      if [[ -n ${devicename} ]] && [[ -n ${sdValue} ]]; then
        if [[ ${#} -eq 0 ]] || [[ "${1}" == "${sdValue}" ]]; then
          if [[ -f /sys/class/block/${sdValue##/dev*/}/size ]]; then
            sizeis="$((512*$(</sys/class/block/${sdValue##/dev*/}/size)))"
            if [[ ${sizeis} -ne 0 ]]; then
              if [[ -n ${printOnce} ]]; then
                echo "${printOnce}"
                unset printOnce
              fi
              description="${devicename//[_-]/ }"
              description="${description//  / }"
              echo "${sdValue}|${sizeis}|${description}"
              missing=0
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
  local disk_devices rc
  disk_devices=$( hwinfo --disk --short  2>/dev/null )
  rc=$?
  echo "${disk_devices}" | tail -n +2  | awk '{print $1}'
  return $rc
}

# Validate that the a device exist and is not mounted
# w/o argument shows a list of drives available
showIdleFlashDrv() {
  local rc disks_list device nmatch tmp tmp2 gotone
  failed=1  # 0 => success, 1 => failed
  disks_list=$( getdiskdev )
  rc=$?
  if [[ 0 -ne $rc ]]; then
    echo -e "\nError getting list of disk drives.\n"
    return 2
  fi

  if [[ "${disks_list}" == "" ]]; then
    echo -e "\nThe list of disk drives came up empty.\n"
    return 3
  fi
  tmp="Device|Size|Description\n"

  for device in ${disks_list}; do
    if [[ 0 -eq ${#} ]] || [[ "${1}" == "${device}" ]]; then
      nmatch=$(findmnt | grep "${device}" | wc | awk '{print $1}')
      rc=$?

      if [[ 0 -eq $rc ]]; then            # do this on success
        if [[ 0 -eq ${nmatch}  ]]; then   # 0 if not mounted
          if [[ ${#} -eq 0 ]]; then       # no argument report available drives
            failed=0
            tmp="${tmp}"$( findDrives "${device}" )"\n"
          elif [[ "${1}" == "${device}" ]]; then
            tmp2=$( findDrives "${device}" )
            if [[ 0 -eq $? ]]; then
              tmp="${tmp}${tmp2}\n"
              failed=0
            else
              failed=4                    # drive not connected / available
            fi
          fi
        else
          failed=5                        # drive mounted
        fi
      fi
    fi
  done

  if [[ ${#} -ne 0 ]]; then
    if [[ 0 -eq $failed ]]; then
      echo -e "Target drive selected for flashing:\n"
      echo -e "${tmp}" | column -s\| -t
    elif [[ 1 -eq $failed ]]; then
      echo "The selected drive, \"${1}\", was not found."
      echo "To flash a drive it must be connected and unmounted."
      echo "When using the file GUI, be sure you use unmount and not eject on the drive."
    elif [[ 4 -eq $failed ]]; then
      echo "The selected drive, \"${1}\", is not connected."
      echo "To flash a drive it must be connected and unmounted."
      echo "When using the file GUI, be sure you use unmount and not eject on the drive."
    elif [[ 5 -eq $failed ]]; then
      echo "The selected drive, \"${1}\", is not available. It is currently mounted. "
      echo "To flash a drive it must be connected and unmounted."
      echo "When using the file GUI, be sure you use unmount and not eject on the drive."
    fi
    return ${failed}
  fi

  if [[ 1 -eq $failed ]]; then
    echo "All drives are mounted. To flash a drive it must not be mounted."
    echo "When using the file GUI, be sure you use unmount and not eject on the drive."
  else
    echo -e "\nThese are the drives currently available:\n"
    echo -e "${tmp}" | column -s\| -t
    echo -e "\nIf you do not see the drive you want to use, make sure it is not mounted."
    echo "When using the file GUI, be sure you use umount and not eject on the drive."
  fi
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
  sudo dd if=${src} of=${flash_dev} bs=4M conv=fsync status=progress

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

if [[ "${flash_dev}" == "" ]]; then
  echo -e "\nInternal script error: shell variable flash_dev was not set\n"
  printUsage
  exit 11

elif ! [[ -b "${flash_dev}" ]]; then
  echo -e "\nTarget drive, \"${flash_dev}\", was not found\n"
  printUsage
  exit 12

else
  if [[ -s ${src} ]]; then
    processFlashWriteDialog
    exit $?
  else
    echo "Disk image file \"${src}\" does not exist or is empty."
    printUsage
    exit 13
  fi
fi

exit 102

# references:
# https://unix.stackexchange.com/questions/52215/determine-the-size-of-a-block-device
# https://superuser.com/questions/763150/how-can-i-know-if-a-partition-is-mounted-or-unmounted
# https://unix.stackexchange.com/a/431968
