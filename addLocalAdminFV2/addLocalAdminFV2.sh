#!/bin/sh

#############################################################################################
#
#  addLocalAdminFV2.sh
#  
#############################################################################################
#
#  Description
#
#  This script will add a user as a FileVault2 user to the system.
#
#############################################################################################
#
#  History
#
#  V1.0 - Initial script
#
#############################################################################################


## Pass the credentials for an admin account that is authorized with FileVault 2
newUser=$4
newPass=$5

if [ "${newUser}" == "" ]; then
	echo "Username undefined.  Please pass the management account username in parameter 4"
	exit 1
fi

if [ "${newPass}" == "" ]; then
	echo "Password undefined.  Please pass the management account password in parameter 5"
	exit 2
fi

## Get the logged in user's name
userName=`defaults read /Library/Preferences/com.apple.loginwindow lastUserName`
echo ${userName}

## Check to see if the encryption process is complete
encryptCheck=`fdesetup status`
statusCheck=$(echo "${encryptCheck}" | grep "FileVault is On.")
expectedStatus="FileVault is On."
if [ "${statusCheck}" != "${expectedStatus}" ]; then
	echo "The encryption process has not completed, unable to add user at this time."
	echo "${encryptCheck}"
	exit 3
fi

## Check to see if the new user is already a FV2 user
userBeforeCheck=`fdesetup list | grep ${newUser} | awk -F, '{print $1}'`
if [ "${userBeforeCheck}" == "${newUser}" ]; then
	echo "The user ${newUser} is already enabled as a FileVault2 user."
	exit 4
fi

## Get the logged in user's password via a prompt
echo "Prompting ${userName} for their login password."
userPass="$(osascript -e 'Tell application "SystemUIServer" to display dialog "Please enter your login password:" default answer "" with title "Login Password" with text buttons {"Ok"} default button 1 with hidden answer' -e 'text returned of result')"

echo "Adding user to FileVault 2 list."

	## This "expect" block will populate answers for the fdesetup prompts that normally occur while hiding them from output
	expect -c "
	log_user 0
	spawn fdesetup add -usertoadd $newUser
	expect \"Enter a password*\"
	send ${userPass}\r
	expect \"Enter the password*\"
	send ${newPass}\r
	log_user 1
	expect eof
	"

## Check to see if the user was added as a FV2 user
userAfterCheck=`sudo fdesetup list | grep ${newUser} | awk -F, '{print $1}'`
if [ "${userAfterCheck}" != "${newUser}" ]; then
	echo "The user ${newUser} was not enabled as a FileVault2 user."
	exit 5
fi

echo "${newUser} has been added to the FileVault 2 list."

exit 0