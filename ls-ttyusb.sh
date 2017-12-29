#!/bin/bash
#
#   Copyright 2017 M Hightower a.k.a. mhightower83 on github.com
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
# ls-ttyusb.sh
#

# Device sysfs attributes and env that may be useful in making a udev rules file
# for a ttyUSB serial device. Note, idVendor and idProduct are required for this
# script to function properly.
itemAttrsList="idVendor\nidProduct\nserial"
itemEnvList="ID_USB_INTERFACE_NUM"

# Default base symlink name
symlinkName=serial
symlinkName=rs232c


printUsage(){
  local namesh=`basename $0`
  cat <<EOF

A simple bash script that extracts information for /dev/ttyUSB devices,
using "udevadm info". Uses the results to generate some comments and build
udev rules entries, that create a symlink for each ttyUSB serial adapter.
All output is presented as lines of comments. Included in the comments is
a starter line for a rules.d entry. Edit as needed.

Usage:

  $namesh [ --list | --rules [symlink name] | --enum [symlink name] | [--help] ]

  Supported operations:

    --list
      Shows a list of ttyUSB devices with info from "lsusb".

    --rules [symlink name]
      Shows a list of ttyUSB devices with a suggested rules entry.
      Optional, symlink name to use in the "SYMLINK+=[symlink name]"
      rules entry. Defaults to $symlinkName.

    --enum [symlink name]
      Similar to rules; however, symlink name will be enumerated.

    --help
      This usage message.

EOF
  return 1
}

uncomment="# "
# unset uncomment

itemAttrsListBraces=$( echo "$itemAttrsList" | sed -e 's/^/ATTRS{/;s/$/}/;s/\\n/}\\nATTRS{/g' )

if [[ -n "$itemAttrsList" ]]; then
  numItemAttrs=$( echo -e "$itemAttrsList" | wc -l )
  unset $(echo -e $itemAttrsList)
else
  numItemAttrs=0
fi

if [[ -n "$itemEnvList" ]]; then
  numItemEnv=$( echo -e "$itemEnvList" | wc -l )
  unset $(echo -e $itemEnvList)
else
  numItemEnv=0
fi

setItemVarables() {
# get and set interesting attributes from the itemAttrsList as variables

  if [[ $numItemAttrs -ne 0 ]]; then
    unset $(echo -e $itemAttrsList)
    while read valueName value;
    do
      unset zzz
#     If valueName occurs more than once for a device, we want the 1st one.
      eval zzz=\$$valueName
      if [[ -z "$zzz" ]]; then
        eval $valueName=\$value
      fi
    done < <( 
        udevadm info $1 -a |
        grep -f <( echo -e $itemAttrsListBraces ) |
        head -$numItemAttrs |
        sed -e 's/^[[:space:]]*//g;s/[[:space:]]*\$//g' |
        sed  's/ATTRS{//;s/}==/ /')
  fi

  if [[ $numItemEnv -ne 0 ]]; then
    unset $(echo -e $itemEnvList)
    while read valueName value;
    do
      unset zzz
#     If valueName occurs more than once for a device, we want the 1st one.
      eval zzz=\$$valueName
      if [[ -z "$zzz" ]]; then
        eval $valueName=\$value
      fi
    done < <( 
        udevadm info $1 -x |
        grep -f <( echo -e $itemEnvList | sed -e 's/$/=/g;s/^/: /g' ) |
        head -$numItemEnv |
        sed -e 's/^E:[[:space:]]*//g;s/[[:space:]]*\$//g' |
        sed  's/=/ /')
  fi
}

listVendorInfo() {

    echo -n "# $1   "
    lsusb | grep -f <(echo $idVendor:$idProduct | sed 's/"//g')
}

printRules() {
# sed s/ATTRS{bInterfaceNumber}/ENV{ID_USB_INTERFACE_NUM}/ ) SYMLINK+=\"firecracker\" 99-usb-serial.rules
  rulesLine="SUBSYSTEM==\"tty\""

  while read item; do
    unset zzz
    eval zzz=\$$item
    if [[ -n "$zzz" ]]; then
      rulesLine="$rulesLine, ATTRS{$item}==$zzz"
    fi
  done < <( echo -e $itemAttrsList )

  while read item; do
    unset zzz
    eval zzz=\$$item
    if [[ -n "$zzz" ]]; then
      rulesLine="$rulesLine, ENV{$item}==\"$zzz\""
    fi
  done < <( echo -e $itemEnvList )

  if [[ -n "$count" ]]; then
    echo "${uncomment}$rulesLine, SYMLINK+=\"$symlinkName$count\""
    count=$(( $count + 1 ))
  else
    echo "${uncomment}$rulesLine, SYMLINK+=\"$symlinkName\""
  fi

  return
}

checkForDuplicateSerialNumbers() {
#   Check for duplicate serial numbers
    if [[ -n "$serial" ]]; then
      # We turn the serial number into a variable, so that we can check for duplicates.
      # The device name is saved in __serialno and the ID is saved in _serialno,
      # where serialno is the serial number found in the udevadm info for the device.

      # using eval to remove quotes
      eval serialValueNameBase=$serial
      serialValueNameId=_ID_${serialValueNameBase}
      eval duplicateId=\$$serialValueNameId
      eval currentId=$idVendor:$idProduct
      if [[ -n "$duplicateId" ]]; then
        eval deviceName=\$_DV_$serialValueNameBase
        if [[ "$currentId" = "$duplicateId" ]]; then
          echo "# *** Devices: $1 and $deviceName share the same ID: $duplicateId and serial number: $serial. ***"
          echo "# *** Use ENV{ID_USB_INTERFACE_NUM} to isolate. ***"
        else
          echo "# *** Devices: $1 ID: $currentId and $deviceName ID: $duplicateId, have the same serial number. ***"
        fi
      fi
      eval $serialValueNameId=$currentId
      eval _DV_${serialValueNameBase}=$1
    else
#     I have seen at least one ttyUSB serial device that did not have a serial attribute.
      echo "# *** This device does not have a serial number attribute. ***"
    fi
}

unset count
if [[ -z "$1" ]]; then
  printUsage >&2
  exit
else
  param1=$1
fi

if [[ "$param1" = "--help" ]]; then
  printUsage
  exit
elif [[ "$param1" = "--rules" ]]; then
  if [[ -n "$2" ]]; then
    symlinkName=$2
  fi
elif [[ "$param1" = "--enum" ]]; then
  if [[ -n "$2" ]]; then
    symlinkName=$2
  fi
# If symlinkName exist, start count after highest enumeration.
  devSymlinkNameBase=/dev/${symlinkName}
  if (ls ${devSymlinkNameBase}* >/dev/null 2>&1); then
    skipn=$(( ${#devSymlinkNameBase} + 1 ))
    count=$(ls ${devSymlinkNameBase}* | cut -c $skipn- | sort -g | tail -1)
    count=$(( $count + 1 ))
  else
    count=1
  fi
  param1=--rules
fi

# Scan through a list os ttyUSB devices and print the lsusb result
numdev=0

# Clear existing variables starting with "_ID_" and "_DV_" so checkForDuplicateSerialNumbers doesn't get confused.
unset $(set | grep -f <(echo -e "^_ID_\n^_DV_") | sed -e 's/=.*$//g')

while read device;
  do
    numdev=$(( $numdev + 1 ))
    echo "#"
    setItemVarables $device;
    listVendorInfo $device --list;
    if [[ "$param1" = "--rules" ]]; then
      printRules;
    fi
    checkForDuplicateSerialNumbers $device
  done < <(
       stat -c"%F %n" /dev/* |
       grep -E ttyUSB[0-9]+$ |
       grep -E ^character |
       cut -d\  -f4)

  if [[ $numdev -eq 0 ]]; then
    echo "# No /dev/ttyUSB... devices found."
  fi
exit

references() {
  cat <<EOF
Reference Material:
# [Persistent names for usb-serial devices](http://hintshop.ludvig.co.nz/show/persistent-names-usb-serial-devices/)


Minor Reference Material:
# [Attributes from various parent devices in a udev rule](https://unix.stackexchange.com/questions/204829/attributes-from-various-parent-devices-in-a-udev-rule)
EOF
}
