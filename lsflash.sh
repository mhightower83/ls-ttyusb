#!/bin/bash
#
#   Copyright 2017 M Hightower
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
# lsflash.sh
#
# Attempts to locate USB connected block devices.
#
namesh="${0##*/}"

printUsage(){
  local namesh=`basename $0`
  cat <<EOF

A simple bash script that attempts to extract information on USB block
devices, which might be flash devices. You must decide which is the
device you are looking for.


Usage:

  $namesh [   ] | [--help]

  Supported operations:

    default
      Shows a list of USB Drives, some of which may be flash drives.
      The /dev/sd... device name, size of the device (which might be 
      a partition) and device name description are reported.

    --help
      This usage message.

EOF
  return 1
}


findUsbFlash() {
  local devLink devicename sdValue sizeis description printOnce
  printOnce="Device|Size|Description"

  for devLink in /dev/disk/by-id/usb-*; do
    devicename="${devLink#/dev/disk/by-id/usb-}"
    sdValue=$(readlink -n -f "${devLink}")
    sizeis="$((512*$(</sys/class/block/${sdValue##/dev*/}/size)))"
    if [[ ${sizeis} -ne 0 ]]; then
      if [[ -n ${printOnce} ]]; then
        echo "${printOnce}"
        unset printOnce
      fi
      description="${devicename//[_-]/ }"
      description="${description//  / }"
      echo "${sdValue}|${sizeis}|${description}"
    fi
  done
}


if [[ ${#} -ne 0 ]] && [[ "${1}" != default ]]; then
  printUsage
else
  findUsbFlash | column -s\| -t
fi

exit 0


# https://unix.stackexchange.com/questions/52215/determine-the-size-of-a-block-device

