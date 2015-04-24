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
    property localPW : "" --local password
    
    global localLoginID --the local username from popup box
    
	on applicationWillFinishLaunching_(aNotification)        
        --get local list of users and build popup menu
        set oldDelimiters to AppleScript's text item delimiters
        set accountsHere to (do shell script "ls -m /Users")
        set AppleScript's text item delimiters to {","}
        set localUserList to text items of accountsHere
        set AppleScript's text item delimiters to oldDelimiters
        set localUserListMod to {""}
        repeat with x in localUserList
            if (x as string is not "Shared")
                if (x as string is not "root")
                    repeat until x does not start with " "  --remove leading spaces
                        set x to text 2 thru -1 of x
                    end repeat
                    set my localUserListMod to localUserListMod & x
                end if
            end if
        end repeat
	end applicationWillFinishLaunching_
	
	on applicationShouldTerminate_(sender)
		return current application's NSTerminateNow
	end applicationShouldTerminate_

    on userChosenPopup_(sender)  --to save the popup selected user in variable
        set localLoginID to sender's selectedItem()'s |title|()
    end userChosenPopup_


    on migrateMe_(sender)
        theWindow's makeFirstResponder_(missing value)
        log "beginning migrateMe section"
        
        --Look to see if we're bound.  If not, warn user
        try
            set ADName to (do shell script "dsconfigad -show |grep Domain |grep -i Active |awk -F= {'print $2'}|awk -F. {'print $1'}") --variable used to determine domain name.  Fails if not bound.
        on error
            set results to display dialog "This computer doesn't seems to be bound to Active Directory.  Are you sure you want to continue?" buttons {"Quit", "Continue"} default button 1 with icon 2
            if button returned of results is "Quit" then tell me to quit
        end try
        
        try  --test local username and password
            do shell script "touch /tmp/toddwashere.txt" user name localLoginID password localPW with administrator privileges
        on error
            display dialog "Your local password (that second box) doesn't appear to work.  Please check it.  If you continue to have problems, reboot and try again" buttons "Cancel" default button 1
            set x to thisIsADeadVariable --force an error to exit the routine
        end try
        
        try  --get userID of AD account.  netLoginID is partners ID name
            set idnet to (do shell script "id -u" & ADName & "\\\\" & netLoginID)
            log "idnet is " & idnet
        on error
            display dialog "Error: cannot find ID " & netLoginID & ".  Are you sure this computer is on the domain and on the network?"  buttons "Cancel" default button 1 with icon 0
            set x to thisIsADeadVariable --force an error to exit the routine
        end try
                
        try  --get userID of  account
            set idlocal to (do shell script "id -u " & localLoginID)
            log "local user id is " & idlocal
        on error
            display dialog "Error: cannot find id " & localLoginID buttons "Cancel" default button 1 with icon 0
            set x to thisIsADeadVariable  --to force cancel of script
        end try

        --see if we are running as the user that is being migrated.  if so, reboot at end.
        set userMatch to "NO"
        set currUserID to (do shell script "id -u")
        if currUserID is idlocal then set userMatch to "YES"
        
        if (netLoginID as string) is (localLoginID as string)
            if userMatch is "YES"
                display dialog "You are logged in as " & netLoginID & " which is also your Network ID.  Please login as a different administrative user before using this tool." buttons "Quit" default button 1
                tell me to quit
            end if
        end if
        
        if userMatch is "YES"
        --    display dialog "You are logged in as " & localLoginID & " and will need to reboot when this process is done." buttons "OK" default button 1 with icon 2
            log "running on current user.  reboot at end forced"
        end if


        --display end text
        if userMatch is "YES"
            display dialog "The migration will run now.  After reboot, please login with your Network user name and password." buttons "Reboot" default button 1 with icon 1
        else
            display dialog "The migration will run now.  After it has completed.  Please logout, then login with your Network user name and password." buttons "Quit" default button 1 with icon 1
        end if

        display dialog "LocalLoginID: " & localLoginID & ". NetLogin is: " & netLoginID --ForDebug


        if localLoginID is netLoginID
            set someResults to display dialog "Your local and Network ID do not match.  You can continue if you have an alternate administrative account on this computer." buttons {"Continue","Cancel"} default button 1 with icon 2
            if button returned of someResults is "Cancel"
                set xyz to gobbledegook  --cause an error
            end if

        if button returned of someResults is "Continue" then
            set localLoginID to text returned of (display dialog "Enter the username of a user with admin rights." default answer "")
            set localPW to text returned of (display dialog "Enter the password for this admin account." default answer "" with hidden answer)
            try
                do shell script "touch /tmp/toddwashere.txt" user name localLoginID password localPW with administrator privileges
            on error
                display dialog "There was an error validating that name and password." buttons "Cancel"
                set xyzyx to gobbledegook --cause an error to stop the program
                try
                    do shell script "rm /tmp/toddwashere.txt" with administrator privileges
                end try
            end try
            
        end if
        end if

        ---################################BEGINNING WORK HERE#################################
        --give admin rights?
        if adminCheck as string is "true"
           do shell script "dscl . -append /Groups/admin GroupMembership " & netLoginID with administrator privileges
            log "Admin rights assigned to " & netLoginID
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

    if csDiskInfo is "" then
        set isEncrypted to true
    else
        set isEncrypted to false
    end if

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
        
        log "creating mobile account..."

        try
            do shell script "/System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n " & ADName & "\\" & netLoginID with administrator privileges
        on error
            log "Error: couldn't create mobileaccount for " & netLoginID
        end try

        log "about to enable filevault..."
        # now enable FileVault
        try
            do shell script "fdesetup add -i < /tmp/fvenable.plist" with administrator privileges
            do shell script "cp /tmp/fvenable.plist /Library/" with administrator privileges
            log "FileVault enabled for " & netLoginID
        on error
            display dialog "Filevault could not add " & netLoginID & " to authorized users." buttons "OK" default button 1 with icon 2
            log "couldn't enable FileVault!"
        end try
    end if


    --move home directory
    if ((netLoginID as string) is not equal to (localLoginID as string)) then   -- error if they are same.
        log "mv /Users/" & localLoginID & " /Users/" & netLoginID & ":end of line"
        do shell script "rm -rf /Users/" & netLoginID with administrator privileges --delete newly created one first
        do shell script "mv /Users/" & localLoginID & " /Users/" & netLoginID with administrator privileges
    else
        log "NetLogin is localLogin - not moving any directories."
    end if

    log "chown -R " & idnet & " /Users/" & netLoginID
    do shell script "chown -R " & idnet & " /Users/" & netLoginID with administrator privileges
    --remove saved state so it won't reopen at reboot.
    try
        do shell script "rm -rf /Users/" & netLoginID & "/Library/Saved\\ Application\\ State/org.partners.MigrateProfile.savedState" with administrator privileges
    end try
    log "savedState cleared"


    --rename Homedir and chown permissions
    log "running DSCL routine now to remove old local account"
    try
        do shell script "dscl . -delete /Users/" & localLoginID with administrator privileges
    on error
        log "error deleting account: " & localLoginID
    end try


    --display end text
    display dialog "about to reboot.  Holding..." buttons "OK" default button 1

    if userMatch is "YES"
        do shell script "reboot" with administrator privileges
    else
        tell me to quit
    end if

    display dialog "The Process has completed!" buttons "OK" default button 1
    tell me to quit
    end migrateMe_
    
    on timeToQuit_(sender)
            tell me to quit
    end timeToQuit

    on makeAnAdmin_(sender)
        do shell script ("dscl . -append /Groups/admin GroupMembership " & adminName) with administrator privileges
        display dialog "The user " & adminName & " now has administrative rights on this computer." buttons "OK" default button 1
    end makeAnAdmin_

end script