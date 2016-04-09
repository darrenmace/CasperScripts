#!/bin/sh
################################################################################
# Author: Darren Mace
# Modified: 2015-08-26
#
# This script utilizes CocoaDialog.app to convert local Mac OS X user accounts
# to mobile accounts.
#
# Based on previous work from:
#   Rich Trouton: https://github.com/rtrouton/rtrouton_scripts/tree/master/rtrouton_scripts/migrate_local_user_to_AD_domain
#   Patrick Gallagher: http://macadmincorner.com/migrate-local-user-to-domain-account/
#   Scott Blake:  https://github.com/MScottBlake/mac_scripts/blob/master/migrateLocalUserToADDomainUser/migrateLocalUserToADDomainUser.sh
#
################################################################################
# Changelog
#
# Version 1.0 - Darren Mace
#
################################################################################
# Variables
#

# Set the path to the cocoaDialog application.
# Will be used to display prompts.
CD="/Applications/CocoaDialog.app/Contents/MacOS/CocoaDialog"

# Set localadmin username
localAdmin=welladmin

# Set local username
localUser=$4

# Set AD username
adUser=$5

# Set AD password
adPassword=$6

# Set localadmin password
adminPassword=$7

################################################################################
# Other Variables (Should not need to modify)
#

FullScriptName=$(basename "${0}")
check4AD=$(/usr/bin/dscl localhost -list . | grep "Active Directory")
osvers=$(/usr/bin/sw_vers -productVersion | awk -F. '{print $2}')
ENCRYPTIONEXTENTS=`diskutil cs list | grep -E "$EGREP_STRING\Has Encrypted Extents" | sed -e's/\|//' | awk '{print $4}'`

################################################################################
# Functions
#

# Generic failure with reason function
die() {
  rv=$("${CD}" ok-msgbox --title "Error" \
  --text "Error" \
  --informative-text "${1}" \
  --no-cancel \
  --float \
  --icon stop)

  if [[ "${rv}" == "1" ]]; then
    echo "Error: ${1}"
    exit 1
  fi
}

# Function to ensure admin privileges
RunAsRoot() {
  ##  Pass in the full path to the executable as $1
  if [[ "$(/usr/bin/id -u)" != "0" ]] ; then
    echo "This application must be run with administrative privileges."
    osascript -e "do shell script \"${1}\" with administrator privileges"
    exit 0
  fi
}

################################################################################

## Check to see if FV2 is enabled
fv2Check=`fdesetup status | grep On\. | awk '{print $3}'`
if [ "${fv2Check}" != "On." ]; then
	die "FileVault is not enabled on this system"
fi

## Check to see if the localadmin is a FV2 user
localAdminCheck=`fdesetup list | grep ${localAdmin} | awk -F, '{print $1}'`
if [ "${localAdminCheck}" != "${localAdmin}" ]; then
	die "The user ${localAdmin} is not enabled as a FV2 user."
fi

# Check to make sure user's profile exists

# Prompt for backup of user profile
rv=( $("${CD}" yesno-msgbox --title "Backup Profile" \
  --text "Do you want to backup ${localUser}'s profile?" \
  --float \
  --no-cancel \
  --icon security) )

if [[ "${rv}" == "1" ]]; then
  if [[ ! -d /Volumes/AD-Backup ]]; then
    die "The backup drive does not seem to be available"
  else
   /usr/bin/rsync -a /Users/"${localUser}" /Volumes/AD-Backup 
   # Display success dialog
    rv=$("${CD}" ok-msgbox --title "Backup Done" \
        --text "${localUser}'s profile has been backed up." \
        --float \
        --no-cancel \
        --icon info)
  fi
elif [[ "${rv}" == "2" ]]; then
  echo "${localUser} declined backup of their local profile"
fi

# Display version information
echo "********* Running ${FullScriptName} *********"

# Execute runAsRoot function to ensure administrative privileges
RunAsRoot "${0}"

# Check for cocoaDialog dependency and exit if not found
if [[ ! -f "${CD}" ]]; then
  echo "Required dependency not found: ${CD}"
  exit 1
fi

# If the machine is bound to AD, then there's no purpose going any further.
if [[ "${check4AD}" == "Active Directory" ]]; then
  die "This machine is bound to Active Directory. Please delete machine from AD first."
fi

# bind to new AD using a JAMF policy to bind to the new AD
# First have to determine which AD to bind to

rv=$("${CD}" standard-dropdown --title "Which Domain?" \
    --text "Please select the domain to bind this mac to!" \
    --float \
    --height 150 \
    --items "Denver" "Lyndhurst" "Seattle" "Burlington" \
    )

return=`echo $rv | cut -d" " -f1`
answer=`echo $rv | cut -d" " -f2`

if [ $return -eq 1 ]; then
     case $answer in
         0)  jamfADPolicyId=3
             newAD="denver.welltok.com"
             ;;
         1)  jamfADPolicyId=866
             newAD="lyndhurst.welltok.com"
             ;;
         2)  jamfADPolicyId=937
             newAD="seattle.welltok.com"
             ;;
         3)  jamfADPolicyId=1246
             newAD="burlington.welltok.com"
             ;;
     esac
else
    die "A Domain was not selected"
fi

# Run the policy to bind the mac to the right AD Domain
jamf policy -id ${jamfADPolicyId} 

### verify that the AD binding was successful
checkAD=`dsconfigad -show | grep -i "active directory domain" | awk '{ print $5 }'`

if [[ "$checkAD" != "$newAD" ]]; then
	die "SOMETHING WENT WRONG AND WE DID NOT BIND TO ${newAD}"
fi

# Display success dialog
rv=$("${CD}" ok-msgbox --title "Mac Bound" \
  --text "This mac has been successfully bound to ${newAD}." \
  --float \
  --no-cancel \
  --icon info)

# End of system binding to AD

# Begin movement of localuser to ADuser

# Validate AD username against spaces
if [[ "${adUser}" != "${adUser%[[:space:]]*}" ]]; then
  die "The Active Directory username cannot contain spaces."
fi

# Determine location of the localuser's home folder
userHome="$(/usr/bin/dscl . read /Users/"${localUser}" NFSHomeDirectory | /usr/bin/cut -c 19-)"

# Get list of groups
echo "Checking group memberships for local user ${localUser}"
lgroups="$(/usr/bin/id -Gn ${localUser})"
echo "${lgroups}"

if [[ $? -eq 0 ]] && [[ -n "$(/usr/bin/dscl . -search /Groups GroupMembership "${localUser}")" ]]; then
# Delete localuser from each group it is a member of
  for lg in "${lgroups}"; do
    /usr/bin/dscl . -delete /Groups/"${lg}" GroupMembership "${localUser}" >&/dev/null
  done
echo "Deleting User from local groups"
fi

# Delete the primary group
if [[ -n "$(/usr/bin/dscl . -search /Groups name "${localUser}")" ]]; then
  /usr/sbin/dseditgroup -o delete "${user}"
  echo "Deleting user primary group"
fi

# Get the localuser's guid and set it as a var
guid="$(/usr/bin/dscl . -read /Users/"${localUser}" GeneratedUID | /usr/bin/awk '{print $NF;}')"
echo "GUID = ${guid}"
if [[ -f /private/var/db/shadow/hash/"${guid}" ]]; then
  /bin/rm -f /private/var/db/shadow/hash/"${guid}"
fi

# Move localuser's home directory out of the way
echo "Moving user's home directory"
/bin/mv "${userHome}" /Users/old_"${localUser}"

# Delete the localuser
echo "deleting local user from system"
/usr/bin/dscl . -delete /Users/"${localUser}"

# Refresh Directory Services
if [[ "${osvers}" -ge 7 ]]; then
  /usr/bin/killall opendirectoryd
  echo "Restarting Opendirectoryd"
else
  /usr/bin/killall DirectoryService
  echo "Restarting DirectoryService"
fi

# Allow service to restart
sleep 20
echo "Here is the AD userid"
/usr/bin/id "${adUser}"

# Check if there's a home folder there already, if there is, exit before we wipe it
if [[ -f /Users/"${adUser}" ]]; then
  die "Oops, theres a home folder there already for ${adUser}. If you don't want that one, delete it in the Finder first, then run this script again."
else
  /bin/mv /Users/old_"${localUser}" /Users/"${adUser}"
  echo "Home directory for '${adUser}' is now located at '/Users/${adUser}'."

  /usr/sbin/chown -R "${adUser}" /Users/"${adUser}"
  echo "Permissions for '/Users/${adUser}' are now set properly."
  
  # Hopefully Temp process to get the cached mobile account created without error
  cp -R /System/Library/User\ Template/English.lproj /Users/"${adUser}"
  chown -R "${adUser}":staff /Users/"${adUser}"
  /System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n "${adUser}" -h /Users/"${adUser}"

  # If HomeBrew exists, chown it to "${adUser}"
  if [[ -f /usr/local/bin/brew ]]; then
    ls -al /usr/local | awk '{print $9}' > /tmp/brew.txt
    for file in $(cat /tmp/brew.txt)
    do
        if  [ "$file" != "." ] && [ "$file" != ".." ]; then
                /usr/sbin/chown -R "${adUser}" /usr/local/"$file"
        fi
    done
    /usr/sbin/chown -R "${adUser}" /Library/Caches/HomeBrew
  fi

  #/System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n "${adUser}"
  echo "Mobile account for ${adUser} has been created on this computer"
fi

# Grant local admin rights to ADuser  
/usr/sbin/dseditgroup -o edit -a "${adUser}" -t user admin
echo "Administrative privileges granted to ${adUser}."

# Display success dialog
rv=$("${CD}" ok-msgbox --title "Successful Migration" \
  --text "Successfully migrated local user account (${localUser}) to Active Directory account (${adUser})." \
  --float \
  --no-cancel \
  --icon info)

# End movement of localuser to ADuser

# Begin add ADuser as FV2 User

### Check to see if FileVault is enabled.  If it is we will need to grab some info from the user
#### this section will get stored in the log file if left on and will store the end user's password and
#### the admin user's password in clear text.  If not testing, disable logging by commenting out lines
#### under the Globals & Logging section above.

if [[ "$ENCRYPTIONEXTENTS" = "Yes" ]]; then
	
	# now we need to add the new UID to FV2
	echo "Adding ${adUser} to FileVault 2 list."

	# create the plist file:
	echo '<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	<key>Username</key>
	<string>'$localAdmin'</string>
	<key>Password</key>
	<string>'$adminPassword'</string>
	<key>AdditionalUsers</key>
	<array>
	    <dict>
	        <key>Username</key>
	        <string>'$adUser'</string>
	        <key>Password</key>
	        <string>'$adPassword'</string>
	    </dict>
	</array>
	</dict>
	</plist>' > /tmp/fvenable.plist  ### you can place this file anywhere just adjust the fdesetup line below

	# now enable FileVault
	fdesetup add -i < /tmp/fvenable.plist
	
	## Check to see if the user was added as a FV2 user
	userAfterCheck=`fdesetup list | grep ${adUser} | awk -F, '{print $1}'`
	if [ "${userAfterCheck}" != "${adUser}" ]; then
		die "The AD user ${adUser} was not enabled as a FV2 user."
	fi

	echo "${adUser} has been added to the FileVault 2 list."

fi

# Display success dialog
rv=$("${CD}" ok-msgbox --title "Successful FV2" \
  --text "Successfully added (${adUser}) as a FileVault2 User." \
  --float \
  --no-cancel \
  --icon info)

# Deleting CocoaDialog
rm -rf /Applications/cocoaDialog.app

