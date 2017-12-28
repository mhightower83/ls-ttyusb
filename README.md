# ls-ttyUSB.sh

This tool was inspired by the information found
[here](http://hintshop.ludvig.co.nz/show/persistent-names-usb-serial-devices/) and
[here](https://unix.stackexchange.com/questions/204829/attributes-from-various-parent-devices-in-a-udev-rule)

A simple bash script that extracts information for /dev/ttyUSB devices,
using "udevadm info". Uses the results to generate some comments and build 
udev rules entries, that create a symlink for each ttyUSB serial adapter. 
All output is presented as lines of comments. Included in the comments 
is a starter line for a rules.d entry. Edit as needed.

```
Usage:

  ls-ttyusb.sh [ --list | --rules [symlink name] | --enum [symlink name] | [--help] ]

  Supported operations:

    --list
      Shows a list of ttyUSB devices with info from "lsusb".

    --rules [symlink name]
      Shows a list of ttyUSB devices with a suggested rules entry.
      Optional, symlink name to use in the "SYMLINK+=[symlink name]"
      rules entry. Defaults to rs232c.

    --enum [symlink name]
      Similar to rules; however, symlink name will be enumerated.

    --help
      This usage message.
```
