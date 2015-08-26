#!/bin/sh

#############################################################################################
#
#  setAutoTimezone.sh
#  
#############################################################################################
#
#  Description
#
#  This script will turn on the auto timezone feature after a system has been wiped
#
#############################################################################################
#
#  History
#
#  V1.0 - Initial script
#
#############################################################################################

/usr/bin/sudo /usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool True

exit 0