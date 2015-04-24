--
--  AppDelegate.applescript
--  MigrateProfile
--
--  Created by admin on 7/14/14.
--  Copyright (c) 2014 Partners. All rights reserved.
--  modified 29Sept2014

script AppDelegate
	property parent : class "NSObject"
	property giveAdminRights : false
	property netLoginID : "abc123"
	property netLoginPW : ""
	property localUserListMod : {"jsmith"}
	property theWindow : missing value
	property adminCheck : true
	property adminName : "" --name to make an admin
	property localPW : ""
    
	global localLoginID --the local username from popup box
	
	on applicationWillFinishLaunching:aNotification
		--get local list of users and build popup menu
		set oldDelimiters to AppleScript's text item delimiters
		set accountsHere to (do shell script "ls -m /Users")
		set AppleScript's text item delimiters to {","}
		set localUserList to text items of accountsHere
		set AppleScript's text item delimiters to oldDelimiters
		set localUserListMod to {""}
		repeat with x in localUserList
			if (x as string is not "Shared") then
				if (x as string is not "root") then
					repeat until x does not start with " " --remove leading spaces
						set x to text 2 thru -1 of x
					end repeat
					set my localUserListMod to localUserListMod & x
				end if
			end if
		end repeat
	end applicationWillFinishLaunching:
	
	on applicationShouldTerminate:sender
		return current application's NSTerminateNow
	end applicationShouldTerminate:
	
	on userChosenPopup:sender --to save the popup selected user in variable
		set localLoginID to sender's selectedItem()'s title()
	end userChosenPopup:
	
	on migrateMe:sender
		theWindow's makeFirstResponder:(missing value)
		log "beginning migrateMe section"
		
		--Look to see if we're bound.  If not, warn user
		try
			set ADStatus to (do shell script "dsconfigad -show |grep -i partners.org") --variable not used, but fails if not bound.
		on error
			set results to display dialog "This computer doesn't seems to be bound to Active Directory.  Are you sure you want to continue?" buttons {"Quit", "Continue"} default button 1 with icon 2
			if button returned of results is "Quit" then tell me to quit
		end try
		
		
		try --get userID of AD account.  netLoginID is partners ID name
			set idnet to (do shell script "id -u " & netLoginID)
		on error
			display dialog "Error: cannot find id " & netLoginID buttons "Cancel" default button 1 with icon 0
		end try
		
		
		try --get userID of  account
			set idlocal to (do shell script "id -u " & localLoginID)
		on error
			display dialog "Error: cannot find id " & localLoginID buttons "Cancel" default button 1 with icon 0
		end try
		
		--see if we are running as the user that is being migrated.  if so, reboot at end.
		set userMatch to "NO"
		set currUserID to (do shell script "id -u")
		if currUserID is idlocal then set userMatch to "YES"
		
		if userMatch is "YES" then
			display dialog "You are logged in as " & localLoginID & " and will need to reboot when this process is done." buttons "OK" default button 1 with icon 2
			log "running on current user.  reboot at end forced"
		end if
		
		--display end text
		if userMatch is "YES" then
			display dialog "The migration is finishing now.  After reboot, please login with your Partners user name and password." buttons "Reboot" default button 1 with icon 1
		else
			display dialog "The migration if finishing now.  Please logout, then login with your Partners user name and password." buttons "Quit" default button 1 with icon 1
		end if
		
		
		--give admin rights?
		if adminCheck as string is "true" then
			do shell script "dscl . -append /Groups/admin GroupMembership " & netLoginID with administrator privileges
		end if
		
		
		--#############add to filevault
		log "beginning FV work"
		set mainBootDrive to (do shell script "df -h /|tail -1|awk '{print $1}'")
		log "boot drive is " & mainBootDrive & ":thank you"
		try
			log "about to get cs status"
			set csDiskInfo to (do shell script "diskutil cs info " & mainBootDrive & " | grep \"is not a CoreStorage disk\"" with administrator privileges)
		on error
			log "no result when looking for Not CoreStorage.  Must be encrypted."
			set csDiskInfo to ""
		end try
		log "csDiskInfo " & csDiskInfo
		
		if csDiskInfo is "" then
			set isEncrypted to true
		else
			set isEncrypted to false
		end if
		
		log "Disk " & mainBootDrive & ": encryption is " & (isEncrypted as string)
		
		
		if isEncrypted is true then
			
			
			# create the plist file:
			do shell script "echo '<?xml version=\"1.0\" encoding=\"UTF-8\"?>' >/tmp/fvenable.plist"
			do shell script "echo '<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">' >>/tmp/fvenable.plist"
			do shell script "echo '<plist version=\"1.0\">' >>/tmp/fvenable.plist"
			do shell script "echo '<dict>' >>/tmp/fvenable.plist"
			do shell script "echo '<key>Username</key>' >>/tmp/fvenable.plist"
			do shell script "echo '<string>'" & localLoginID & "'</string>' >>/tmp/fvenable.plist"
			do shell script "echo '<key>Password</key>' >>/tmp/fvenable.plist"
			do shell script "echo '<string>'" & localPW & "'</string>' >>/tmp/fvenable.plist"
			do shell script "echo '<key>AdditionalUsers</key>' >>/tmp/fvenable.plist"
			do shell script "echo '<array>' >>/tmp/fvenable.plist"
			do shell script "echo '<dict>' >>/tmp/fvenable.plist"
			do shell script "echo '<key>Username</key>' >>/tmp/fvenable.plist"
			do shell script "echo '<string>'" & netLoginID & "'</string>' >>/tmp/fvenable.plist"
			do shell script "echo '<key>Password</key>' >>/tmp/fvenable.plist"
			do shell script "echo '<string>'" & netLoginPW & "'</string>' >>/tmp/fvenable.plist"
			do shell script "echo '</dict>' >>/tmp/fvenable.plist"
			do shell script "echo '</array>' >>/tmp/fvenable.plist"
			do shell script "echo '</dict>' >>/tmp/fvenable.plist"
			do shell script "echo '</plist>' >> /tmp/fvenable.plist"
			log "/tmp/fvenable.plist file created"
			
			log "creating mobile account next"
			try
				do shell script "/System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n " & netLoginID with administrator privileges
			on error
				log "Error: couldn't create mobileaccount for " & netLoginID
			end try
			
			log "about to enable filevault"
			# now enable FileVault
			try
				do shell script "fdesetup add -i < /tmp/fvenable.plist"
			on error
				display dialog "Filevault could not add " & netLoginID & " to authorized users." buttons "OK" default button 1 with icon 2
			end try
			log "FileVault enabled for " & netLoginID
		end if
		
		--move home directory
		if ((netLoginID as string) is not equal to (localLoginID as string)) then -- error if they are same.
			log "mv /Users/" & localLoginID & " /Users/" & netLoginID
			do shell script "mv /Users/" & localLoginID & " /Users/" & netLoginID with administrator privileges
		end if
		log "chown -R " & netLoginID & " /Users/" & netLoginID
		do shell script "chown -R " & netLoginID & " /Users/" & netLoginID with administrator privileges
		log "chown done"
		--remove saved state so it won't reopen at reboot.  
		try
			do shell script "rm -rf /Users/" & netLoginID & "/Library/Saved\\ Application\\ State/org.partners.MigrateProfile.savedState"
		end try
		log "savedState cleared"
		
		
		
		--rename Homedir and chown permissions
		log "running DSCL routine now to rename old local account"
		try
			do shell script "dscl . -delete /Users/" & localLoginID with administrator privileges
		on error
			log "error deleting " & localLoginID
		end try
		
		
		--display end text
		if userMatch is "YES" then
			do shell script "reboot" with administrator privileges
		else
			tell me to quit
		end if
		
	end migrateMe:
	
	on timeToQuit:sender
		tell me to quit
	end timeToQuit:
	
	on makeAnAdmin:sender
		do shell script ("dscl . -append /Groups/admin GroupMembership " & adminName) with administrator privileges
		display dialog "The user " & adminName & " now has administrative rights on this computer." buttons "OK" default button 1
	end makeAnAdmin:
	
end script