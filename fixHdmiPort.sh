#!/bin/bash
#
#   Copyright 2018 M Hightower
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
#
# Fix Unplugged HDMI Display Port
#
# An assumption is that at boot time if a display is attched the system
# selects good "fbset" geometry values. We will run 
# "fixHdmiPort.sh --update-cache" from rc.local to archive those
# values for later.
#
# At some later event, such as USB keybaord plugged in, we will run
# "fixHdmiPort.sh --power-on" which will wait for the display device to
# be  plugged in. This is assumed true when tvservice -n is successful
# and reports back a string "device_name=..."
#
# Some ideas were taken from these sources:
#   http://laurenceoflosangeles.blogspot.com/2015/08/configuring-udev-to-run-script-when-usb.html
#   https://www.raspberrypi.org/forums/viewtopic.php?t=12332#p952362
#
#
# You will need a .rules file in /etc/udev/rules.d/ with a line like this:
#
# ACTION=="add", SUBSYSTEM=="hidraw", KERNEL=="hidraw*", RUN+="/usr/local/bin/fixHdmiPort.sh --power-on 30"
#
#   OR
#
# I don't think this long a time is needed; however, if the need
# arises to wait a really long time, this is how it should be done.
# This options requires that "at" be installed.
# ACTION=="add", SUBSYSTEM=="hidraw", KERNEL=="hidraw*", RUN+="/usr/local/bin/fixHdmiPort.sh --detach 120"


# Where things are or go
# tvservice="/opt/vc/bin/tvservice"
tvservice="/usr/bin/tvservice"
fbset="/bin/fbset"
udevadm="/sbin/udevadm"
systemctl="/bin/systemctl"

displayCache="/usr/local/etc/displayCache"
debuglog=/tmp/debug.log
#debuglog=/dev/null

udev_restart="udev-restart-after-boot.service"
udev_rules="10-hid-trigger.rules"
rc_local="rc.local"

udev_restart_full="/etc/systemd/system/${udev_restart}"
udev_rules_full="/etc/udev/rules.d/${udev_rules}"
rc_local_full="/etc/${rc_local}"

eval namesh_full="${0}"
[[ "${namesh_full:0:2}" = "./" ]] && namesh_full="`pwd`/${namesh_full#./}"
[[ -s "${namesh_full}" ]] && [[ -x "${namesh_full}" ]] || { echo "**** Internal logic error in expanding path">&2; exit 100; }
namesh="${namesh_full##*/}"

mutexBase="/var/run/${namesh}.mutex"
mutexCache="${mutexBase}.cache"
mutexHid="${mutexBase}.hid"

returnSuccess() {
  echo "returnSucess ${*}" >&2
  return 0
}

# A sanbox for testing, just run the script from a folder named sandbox.
if [[ "${namesh_full##*/sandbox/}" = "${namesh_full##*/}" ]]; then
sandbox="${namesh_full%/${namesh}}"
udev_restart_full="${sandbox}/system/${udev_restart}"
udev_rules_full="${sandbox}/udev/${udev_rules}"
rc_local_full="${sandbox}/etc/${rc_local}"
displayCache="${sandbox}/etc/displayCache"
debuglog="${sandbox}/debug.log"
mutexBase="${sandbox}/run/${namesh}.mutex"
mutexCache="${mutexBase}.cache"
mutexHid="${mutexBase}.hid"
mkdir -p "${sandbox}/system/" "${sandbox}/udev/" "${sandbox}/etc/" "${sandbox}/run/"

tvservice="returnSuccess ${tvservice}"
fbset="returnSuccess ${fbset}"
udevadm="returnSuccess ${udevadm}"
systemctl="returnSuccess ${systemctl}"
else
unset sandbox
fi

uninstallTag="${namesh}:"

# How long to wait for a Display to be plugged in. (seconds)
timeOut=30

# Minimum mutex hold time for "--power-on" option. This guards against
# running multiple instance when launch by udev with broad rule specifications.
minShieldTime=5


trap "echo \"($$) Failed \`date '+%s'\`\";[[ ${debuglog} != \"/dev/null\" ]] && [[ -f ${debuglog} ]] && chmod 666 ${debuglog};" EXIT

option="${1,,}"
shift

if [[ "${option}" = "--detach" ]]; then
  if ! [[ -e "${mutexhid}" ]]; then
    # this works - keep
    echo "${namesh_full} --power-on ${1} >${debuglog} 2>&1; chmod 666 ${debuglog}" | /usr/bin/at now
#
# Note, if I don't detach in some way udev will let me run and call
# sleep over a period of 57 seconds before it starts complaining.
# In general that should be long enough, then there is no need to install "at"
# and use --detach.
#
# These don't work when called via udev RUN+=, they die in their sleep:
# udev daemon appears to terminate detached jobs, that try to sleep,
# with extream prejudice. "trap ..."  do not get an opertunity to cleanup.
#   { $( nohup ${0} --power-on </dev/null >/dev/null 2>&1 & ) & } &
#   { $( ${0} --power-on </dev/null >>${debuglog} 2>&1 & ) & } &
#   ${0} --power-on </dev/null >>${debuglog} 2>&1 & disown
#   { nohup "${0}" "--power-on" </dev/null >/dev/null 2>&1 & } &
#   { nohup "${0}" "--power-on" & } &
  fi
  exit 0
fi

printVar() {
  eval var="\${$1}"
  echo "${1}=${var}"
}

needRoot() {
  [[ -n "${sandbox}" ]] && return 0;
  if [[ $UID -ne 0 ]]; then
    echo ""
    echo "This function needs to be run as root. Please rerun with sudo:"
    echo "  sudo ${namesh_full} ${option} ${*}"
    echo ""
    return 100
  fi
  return 0;
}

doMutex() {
  trap "echo \"($$) doMutex failed \`date '+%s'\`\"; [[ ${debuglog} != \"/dev/null\" ]] && [[ -f ${debuglog} ]] && chmod 666 ${debuglog};" EXIT
  echo "($$) doMutex: `date '+%s'`"
  if ! ( mkdir "${1}" ); then
    # An instance is already running - get out.
    return 100
  fi
  echo "($$) Got mutex `date '+%s'`"
  trap "echo \"($$) Exit \`date '+%s'\`\";rmdir \"${1}\";[[ ${debuglog} != \"/dev/null\" ]] && [[ -f ${debuglog} ]] && chmod 666 ${debuglog};" EXIT
}


updateDisplayCache() {
  local rc
  doMutex "${mutexCache}" || return $?

  [[ -n "${1}" ]] && eval displayCache="${1}"
  [[ -n "${displayCache}" ]] || return 1;
  [[ -f "${displayCache}" ]] || touch "${displayCache}";
  name=`${tvservice} -n 2>/dev/null`
  name="${name#device_name=}"
  [[ -z "${name}" ]] && return 2;

  geometry=`${fbset} -s | grep geometry | sed "s/^\s*geometry\s*//"`
  [[ -z "${geometry}" ]] && return 3;

  geometryOld=`grep "${name}" ${displayCache} | head -1 | sed "s/^.*=//"`
  [[ "${geometry}" = "${geometryOld}" ]] && return 4;


  if [[ -n "${geometryOld}" ]]; then
    sed -i "s/^\s*${name}\s*=.*$/${name}=${geometry}/" ${displayCache}
  else
    echo "${name}=${geometry}" >>${displayCache}
  fi
  return 0
}

waitForDisplayAndSetup() {
  # Wait for Display to be connected to HDMI port
  # This is indicated by the device_name becoming available
  unset name
  echo "($$) timeOut=${1}" >>${debuglog}
  loopCount=0
  while [[ -z "${name}" ]]; do
    name=`${tvservice} -n 2>/dev/null`
    name="${name#device_name=}"
    if [[ -z "${name}" ]]; then
      [[ $loopCount -ge ${1} ]] && return 1
      loopCount=$(( $loopCount + 1 ))
      echo "($$) Display not connected. Sleep at `date '+%s'`"
      sleep 1
      echo "($$) Awake at `date '+%s'`"
    fi
  done;

  # Power on device
  ${tvservice} -p

  # Set Frame Buffer Gepmetry - if available
  unset geometry
  # [[ -n "${2}" ]] && eval displayCache="${2}"
  if [[ -n "${displayCache}" ]] && [[ -f "${displayCache}" ]]; then
    geometry=`grep "${name}" ${displayCache} | head -1 | sed "s/^.*=//"`
  fi
  if [[ -z "${geometry}" ]]; then
    # try and estamate some values
    local sizeXY sizeX sizeY overscan
    overscan=15
    sizeXY=`${tvservice} -s | sed -e "s/^.*],\s*\([0-9]*x[0-9]*\).*$/\1/"`
    sizeX=$(( ${sizeXY%x*} - $overscan ))
    sizeY=$(( ${sizeXY#*x} - $overscan ))
    geometry="${sizeX} ${sizeY} ${sizeX} ${sizeY} 16"
    echo "estamated: fbset --geometry ${geometry}"
  fi
  ${fbset} --geometry ${geometry}
  # ${fbset} --timings 0 0 0 0 0 0 0
  # ${fbset} -rgba 8/16,8/8,8/0,8/24
  # Don't understand why, but display stays blank, until we do this calls.
  ${fbset} -depth 8
  ${fbset} -depth 16
  return 0
}

powerOnHdmiDevice() {
  local rc
  doMutex "${mutexHid}" || return $?

  elapseTime=`date '+%s'`
  waitForDisplayAndSetup "${1}"
  rc=$?
  # The udev rule we use are not very specific so we
  # sit with mutex set to block duplicate udev invocation
  # from multiple simlilar events
  elapseTime=$(( `date '+%s'` - ${elapseTime} ))
  [[ ${elapseTime} -lt 15 ]] && sleep $(( ${minShieldTime} - ${elapseTime} ))
  return $rc
}

#
#
#
#

if [[ "--update-cache" = "${option}" ]]; then
  needRoot || exit $?
  updateDisplayCache
  exit 0
fi

# If no option and NOT running interactively, make an assumption of what to do
[[ -z "${PS1}" ]] && [[ -z "${option}" ]] && option="--power-on"

if [[ "--power-on" = "${option}" ]]; then
  needRoot || exit $?
  [[ -n "${1}" ]] && timeOut=${1}
  powerOnHdmiDevice "${timeOut}" >>${debuglog} 2>&1
  rc=$?
  [[ -z "${PS1}" ]] && rc=0
  exit $rc
fi


#
#
# Install helpers
#
#

rc_local_txt() {
cat >&2 << /EOF

Append this text at the bottom of your "${rc_local_full}" file, 
just before the "exit 0" command.

/EOF

cat << /EOF
# ${1} - Do not remove these tags. It is used to automate uninstall.
# ${1} If a monitor is connected to the HDMI power, capture a copy of
# ${1} the Frame Buffer geometry values.
if [ -s "${namesh_full}" ] && [ -x "${namesh_full}" ]; then # ${1}
  ${namesh_full} --update-cache # ${1}
fi # ${1}
exit 0
/EOF
}

udev_rule_txt() {
cat >&2 << /EOF

You will need a .rules file in ${udev_rules_full}
with something like this:

/EOF
cat << /EOF
#
# When a keybaord, mouse, or other HID device is plugged in, run a bash script
# that polls every second (up to 30 seconds) waiting for a display to be
# plugged into the HDMI port. Then run "tvservice -p" to power on device, etc.
# Change the 30 for longer or short wait periods up to 57 secs.
# ${1}
ACTION=="add", SUBSYSTEM=="hidraw", KERNEL=="hidraw*", RUN+="${namesh_full} --power-on 30"
/EOF
}

udev_hack_txt() {
cat >&2 << /EOF

It has been observed that  the systemd-udevd daemon, on Raspbian systems,
is running with with the root filesystem, "/", mounted RO! Thus all 
scripts launched by it, don't have write permission on some files/sockets.
This service attempts to work around that problem.

/EOF

cat << /EOF
#
# This is taken from:
#   https://github.com/raspberrypi/linux/issues/2497#issuecomment-450255862
#
# Goes in:
#   ${udev_restart_full}
#
# install by:
#   sudo systemctl daemon-reload
#   sudo systemctl enable ${udev_restart}
#   sudo systemctl start ${udev_restart}
#
# ${1}
[Unit]
Description=Restart udev service after boot (ugly hack to work around file system being readonly)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/systemctl restart systemd-udevd.service

[Install]
WantedBy=multi-user.target
/EOF
}

printusage() {
cat << /EOF

Usage for "${namesh_full}":

  Option used to start script to activate HDMI port when display
  is connected. Default option, when NOT running interactively.
    ${namesh} --power-on [optional, how long to wait in seconds]

  Option used from rc.local to capture geometry of a working
  display and its device_name value. The information is added
  to "${displayCache}".
    ${namesh} --update-cache

  Prints the text that needs to be added to "${rc_local_full}".
    ${namesh} --print-rclocal

  Prints the text for .rules file you need to place in
  /dev/udev/rules.d/
    ${namesh} --print-udev-rule

  Prints the text for a systemd service to work around a
  problem with udev startup.
    ${namesh} --print-udev-hack

  Write files of the above print text to the current directory.
  Will overwrite existing files w/o warning.
    ${namesh} --save-files

  Option for udev .rules to use to run scripts that detach and
  take a very long time. In most cases will not be needed.
    ${namesh} --detach

  Prints this message.
    ${namesh} --help

/EOF
}

trap "" EXIT
generateFiles() {
  rc_local_txt >"${rc_local}.plus"
  echo "Saved to: ${rc_local}.plus"
  udev_rule_txt >"${udev_rules}"
  echo "Saved to: ${udev_rules}"
  udev_hack_txt >"${udev_restart}"
  echo "Saved to: ${udev_restart}"
  echo ""
}

installit() {
  local rc
  needRoot || return $?;

  # setup udev rule
  echo -e "\nWriting udev rules file ${udev_rules_full} ..."
  if [[ -s "${udev_rules_full}" ]]; then
    echo ""
    echo "The file \"${udev_rules_full}\" already exit,"
    echo "no changes made. Please verify its content is equal to:"
    echo ""
    udev_rule_txt 2>/dev/null
  else
    udev_rule_txt "[${uninstallTag}] - Install tag, do not remove." 2>/dev/null >"${udev_rules_full}"
  fi

  # Install udev deamon hack/fix
  echo -e "\nInstalling ${udev_restart_full} ..."
  if [[ -s "${udev_restart_full}" ]]; then
    echo ""
    echo "The file \"${udev_restart_full}\""
    echo "already exist. No changes made. Please verify its content is equal to:"
    echo ""
    udev_hack_txt 2>/dev/null
  else
    udev_hack_txt "[${uninstallTag}] - Install tag, do not remove." 2>/dev/null >"${udev_restart_full}"
    ${systemctl} daemon-reload
    ${systemctl} enable "${udev_restart}"
    ${systemctl} start "${udev_restart}"
  fi

  # Update rc.local
  echo -e "\nModifying ${rc_local_full} ..."
  # Expression inspired by: https://unix.stackexchange.com/questions/60994/how-to-grep-lines-which-does-not-begin-with-or
  if grep -qixE '[[:blank:]]*[^#].*'"${namesh}"'[[:blank:]][[:blank:]]*--update-cache' "${rc_local_full}"; then
    echo ""
    echo "\"${namesh} --update-cache\" was already in the file \"${rc_local_full}\""
    echo "no changes made. Please verify the content is equal to:"
    rc_local_txt 2>/dev/null

    # Make backup copy of rc.local and remove trailing empty lines at bottom of file
  elif \
    cp "${rc_local_full}" "${rc_local_full}.bak" \
    && echo "" >>"${rc_local_full}.bak" \
    && chmod 755 "${rc_local_full}.bak" \
    && echo "Created backup file \"${rc_local_full}.bak\"" \
   ; then
    # sed incantation inspired by https://unix.stackexchange.com/a/41849
    # changed to this one https://unix.stackexchange.com/a/323951
    # use of tac inspired by https://stackoverflow.com/a/23894449
    echo "Triming empty lines ..."
    tac "${rc_local_full}.bak" | sed '/\S/,$!d' | tac > "${rc_local_full}~~~" && mv "${rc_local_full}~~~" "${rc_local_full}"
    echo "Checking for a last command of \"exit 0\" ..."
    lastLine=`wc -l "${rc_local_full}" | cut -d\  -f1`
    exitLine=`grep -nixE '[^#]*exit[[:blank:]][[:blank:]]*00*[[:blank:]]*(#.*)*$' "${rc_local_full}" | cut -d: -f1 | tail -1`
    # Is exit 0 the last line
    if [[ ${exitLine} -eq ${lastLine} ]]; then
      echo "Deleting last line with \"exit 0\" command ..."
      [[ -n "${lastLine}" ]] && sed -i -e "${lastLine}d" "${rc_local_full}"
    else
      # Punt, let the user edit the file and finish the job.
      echo "##### The above was the last line. [${uninstallTag}]" >>"${rc_local_full}"
      echo ""
      echo "\"exit 0\" does not appear to be the last command in your system's"
      echo "\"${rc_local_full}\" file."
      echo "Make changes as needed, such that the code tagged with"
      echo "\"[${uninstallTag}]\", is in the main execution path."
      echo ""
    fi
    echo "Appending commands with a new \"exit 0\" to rc.local ..."
    rc_local_txt "[${uninstallTag}]" 2>/dev/null >>"${rc_local_full}"
  else
      echo "Unable to proceed. Please make the needed changes to rc.local."
      echo "Add the content shown below to \"${rc_local_full}\":"
      rc_local_txt 2>/dev/null
  fi
  echo -e "\nRestarting udevadm ..."
  ${udevadm} control --reload-rules && ${udevadm} trigger
  echo -e "\nFinished."
  return 0
}

removeFile() {
  if [[ -n "${1}" ]] && [[ -f "${1}" ]]; then
    if rm ${1}; then
      echo "Successfuly removed ${1}."
    else
      echo "Failed to remove ${1}."
      echo "You will need to remove it by hand."
    fi
  fi
}

uninstallHelp() {
cat >&2 << /EOF

Typical commands for complete uninstall of ${namesh}
Must run as root:

/EOF

cat << /EOF

rm "${udev_rules_full}"
${udevadm} control --reload-rules && ${udevadm} trigger

${systemctl} stop "${udev_restart}"
${systemctl} disable "${udev_restart_full}"
${systemctl} daemon-reload
rm "${udev_restart_full}"

if cp  "${rc_local_full}" "${rc_local_full}.bak"; then
  grep -v "\[${uninstallTag}\]" "${rc_local_full}" > "${rc_local_full}~~~~~" \
  && mv "${rc_local_full}~~~~~" "${rc_local_full}" \
  || ( [[ -f "${rc_local_full}~~~~~" ]] && rm "${rc_local_full}~~~~~" )
fi

# rm "${0}"

/EOF
return 0
}
uninstallit() {
  local rc
  needRoot || return $?;

  uninstallDelay=5
  echo -e "\nBegin uninstalling ${udev_rules} ..."
  sleep ${uninstallDelay}
  removeFile "${udev_rules_full}"
  ${udevadm} control --reload-rules && ${udevadm} trigger

  echo -e "\nBegin uninstalling ${udev_restart} ..."
  sleep ${uninstallDelay}
  ${systemctl} stop "${udev_restart}"
  ${systemctl} disable "${udev_restart}"
  ${systemctl} daemon-reload
  removeFile "${udev_restart_full}"

  echo -e "\nBegin uninstalling changes made to ${rc_local_full} ..."
  sleep ${uninstallDelay}
  if [[ -f "${rc_local_full}" ]]; then
    if cp  "${rc_local_full}" "${rc_local_full}.bak"; then
      grep -v "\[${uninstallTag}\]" "${rc_local_full}" > "${rc_local_full}~~~~~" \
      && chmod 755  "${rc_local_full}~~~~~" \
      && mv "${rc_local_full}~~~~~" "${rc_local_full}" \
      && echo -e "uinstall finished.\n"\
      || ( [[ -f "${rc_local_full}~~~~~" ]] && rm "${rc_local_full}~~~~~"  \
         && echo -e "\nAn error occured in removing ${namesh} from ${rc_local_full}.\n" )
    else
      echo ""
      echo "Failed to create backup file of ${rc_local_full}."
      echo "Edit ${rc_local_full} by hand to finish unstall"
      echo ""
    fi
  fi
}

[[ "${option}" = "--print-rclocal"   ]] && { rc_local_txt;  exit 0; }
[[ "${option}" = "--print-udev-rule" ]] && { udev_rule_txt; exit 0; }
[[ "${option}" = "--print-udev-hack" ]] && { udev_hack_txt; exit 0; }
[[ "${option}" = "--save-files"      ]] && { generateFiles; exit 0; }
[[ "${option}" = "--help"            ]] && { printusage;    exit 0; }
# Experimental install and uninstall
[[ "${option}" = "--install"         ]] && { installit;     exit 0; }
[[ "${option}" = "--uninstall-help"  ]] && { uninstallHelp; exit 0; }
[[ "${option}" = "--uninstall"       ]] && { uninstallit;   exit 0; }

printusage
exit 0


miscdebugscraps() {
  printVar "displayCache"
  printVar "geometry"
  printVar "geometryOld"
  printVar "name"
}

