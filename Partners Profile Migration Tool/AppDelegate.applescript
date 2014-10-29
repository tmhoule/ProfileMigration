--
--  AppDelegate.applescript
--  Partners Profile Migration Tool
--
--  Created by Houle, Todd on 10/20/14.
--  Copyright (c) 2014 Partners. All rights reserved.
--

script AppDelegate
	property parent : class "NSObject"
	property giveAdminRights : false
    property netLoginID : "abc123"
    property netLoginPW : ""
    property localUserListMod : {"jsmith"}
    property theWindow : missing value
    property adminCheck : true
    property localAdminPW : ""  --password of admin user used during migration
    property localNetIDUser :  ""  --user to make admin on 2nd tab

    global isEncrypted
    global localLoginID  --local user to migrate from popup
    global localAdminUser --local admin user for filefault encryption
    global idnet  --UID of Partners ID
    
    
	on applicationWillFinishLaunching_(aNotification)
		-- Insert code here to initialize your application before any files are opened
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

        checkForEncryption_("one")
	end applicationWillFinishLaunching_

    on adminUserHelp_(sender)
        display dialog "The Admin User is a user on the computer who has administrative rights.  If FileVault is enabled, this user must also be enabled to unlock the computer (defined in System Preferences)." buttons "OK" default button 1 with icon 1
    end adminUserHelp_

    on adminPasswordHelp_(sender)
        display dialog "This field is for the password of the admin account on the computer.  This is not your Partners password or the password for the account you are migrating." buttons "OK" default button 1 with icon 1
    end adminUserHelp_

	on applicationShouldTerminate_(sender)
		-- Insert code here to do any housekeeping before your application quits 
		return current application's NSTerminateNow
	end applicationShouldTerminate_

    on userChosenPopup_(sender)  --to save user to migrate from popup
        set localLoginID to sender's selectedItem()'s |title|()
        log "Will migrate " & localLoginID
    end userChosenPopup_

    on userAdminChosenPopup_(sender)  --to save name of Admin user
    set localAdminUser to sender's selectedItem()'s |title|()
        log "Admin user to use is " & localAdminUser
        if isEncrypted is true
            display dialog "Please make sure " & localAdminUser & " is enabled for FileVault." buttons "OK" default button 1 with icon 1
        end if
    end userAdminChosenPopup_

    on quitTime_(sender)
        tell me to quit
    end quitTime_

    on makeAnAdmin_(sender)
        theWindow's makeFirstResponder_(missing value)
        do shell script ("dscl . -append /Groups/admin GroupMembership " & localNetIDUser) with administrator privileges
        display dialog "The user " & localNetIDUser & " now has administrative rights on this computer." buttons "OK" default button 1
    end makeAnAdmin_


    on checkPartnersIDMatchesLocalID_(sender)
        if isEncrypted is true
            if (localAdminUser as string) is (localLoginID as string) then
                if (localAdminUser as string) is (netLoginID as string) then
                    display dialog "Sorry, your Partners ID, Admin user, and computer login ID cannot all match while the machine is encrypted.  Create a new admin account with FileVault access to migrate." buttons "Cancel" default button 1
                    set x to thisIsADeadVariable  --to force cancel of script
                end if
            end if
        end if
    end checkPartnersIDMatchesLocalID_

    on deleteUserAccount()
        log "running DSCL routine now to remove old local account"
        try
            do shell script "dscl . -delete /Users/" & localLoginID user name localAdminUser password localAdminPW with administrator privileges
            on error
            log "error deleting account: " & localLoginID
        end try
    end deleteUserAccount

    on beginMigration_(sender)
        theWindow's makeFirstResponder_(missing value)
        log "beginning migrateMe section"
        
        --check if all the ID's match
        checkPartnersIDMatchesLocalID_(sender)
        
        --Look to see if we're bound.  If not, warn user
        try
            set ADStatus to (do shell script "dsconfigad -show |grep -i partners.org")  --variable not used, but fails if not bound.
            on error
            set results to display dialog "This computer doesn't seems to be bound to Active Directory.  Are you sure you want to continue?" buttons {"Quit", "Continue"} default button 1 with icon 2
            if button returned of results is "Quit" then tell me to quit
        end try

        
        try  --get userID of AD account.  netLoginID is partners ID name
            set idnet to (do shell script "id -u partners\\\\" & netLoginID)
            log "idnet is " & idnet
        on error
            display dialog "Error: cannot find ID " & netLoginID & ".  Are you sure this computer is on the domain and on the network?"  buttons "Cancel" default button 1 with icon 0
            set x to thisIsADeadVariable --force an error to exit the routine
        end try
        
        try  --get userID of local account
            set idlocal to (do shell script "id -u " & localLoginID)
            log "local user id is " & idlocal
        on error
            display dialog "Error: cannot find id " & localLoginID & ".  This is a major error." buttons "Cancel" default button 1 with icon 0
            set x to thisIsADeadVariable  --to force cancel of script
        end try

        try  --test local username and password
            do shell script "touch /tmp/toddwashere.txt" user name localAdminUser password localAdminPW with administrator privileges
            do shell script "rm /tmp/toddwashere.txt" user name localAdminUser password localAdminPW with administrator privileges
        on error
            display dialog "Your local password (that second box) doesn't appear to work.  Please check it.  If you continue to have problems, reboot and try again" buttons "Cancel" default button 1
            set x to thisIsADeadVariable --force an error to exit the routine
        end try

        ---################################BEGINNING WORK HERE#################################
        --give admin rights?
        if adminCheck as string is "true"
            do shell script "dscl . -append /Groups/admin GroupMembership " & netLoginID user name localAdminUser password localAdminPW with administrator privileges
            log "Admin rights assigned to " & netLoginID
        end if

        if (netLoginID as string) is (localLoginID as string)
            deleteUserAccount()
        end if

        if isEncrypted is true
            addToFileVault_("none")
        end if

        --move home directory and change permissions
        if ((netLoginID as string) is not equal to (localLoginID as string)) then   -- error if they are same.
            log "mv /Users/" & localLoginID & " /Users/" & netLoginID & ":end of line"
            do shell script "rm -rf /Users/" & netLoginID user name localAdminUser password localAdminPW with administrator privileges --delete newly created one first
            do shell script "mv /Users/" & localLoginID & " /Users/" & netLoginID user name localAdminUser password localAdminPW with administrator privileges
        else
            log "NetLogin is localLogin - not moving any directories."
        end if
        log "chown -R " & idnet & " /Users/" & netLoginID
        do shell script "chown -R " & idnet & " /Users/" & netLoginID user name localAdminUser password localAdminPW with administrator privileges
        --remove saved state so it won't reopen at reboot.
        try
            do shell script "rm -rf /Users/" & netLoginID & "/Library/Saved\\ Application\\ State/org.partners.MigrateProfile.savedState" user name localAdminUser password localAdminPW with administrator privileges
        end try

        if (netLoginID as string) is not (localLoginID as string)
            deleteUserAccount()
        end if


        display dialog "The Process has completed!" buttons "OK" default button 1
        do shell script "reboot" user name localAdminUser password localAdminPW with administrator privileges

    end beginMigration_

    on checkForEncryption_(sender)
        set FVOnOff to do shell script "fdesetup status|head -1|awk '{print $3}'"
        
        if (FVOnOff as string) is ("Off." as string) then
            set isEncrypted to false
            else
            set isEncrypted to true
        end if
        log "Encryption for disk is " & isEncrypted
    end checkForEncryption_

    on addToFileVault_(sender)
        log "begging sub addToFileVault"

        
        if (netLoginID as string) is (localLoginID as string)
            log "mv /Users/" & (netLoginID) &  " /Users/" & (netLoginID) & ".bkup"
            do shell script "mv /Users/" & (netLoginID) &  " /Users/" & (netLoginID) & ".bkup" user name localAdminUser password localAdminPW with administrator privileges
        end if
        --try
            log "creating mobile account...  partners\\\\" & netLoginID
            do shell script "/System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n partners\\\\" & netLoginID user name localAdminUser password localAdminPW with administrator privileges
        --on error
        --    log "Error: couldn't create mobileaccount for " & netLoginID
        --end try

        if (netLoginID as string) is (localLoginID as string)
            log "rm -rf /Users/" & (netLoginID)
            do shell script "rm -rf /Users/" & (netLoginID) user name localAdminUser password localAdminPW with administrator privileges
            log "mv /Users/" & netLoginID & ".bkup /Users/" & netLoginID 
            do shell script "mv /Users/" & netLoginID & ".bkup /Users/" & netLoginID user name localAdminUser password localAdminPW with administrator privileges
            log "cleanup done."
        end if


        log "chown -R " & idnet & " /Users/" & netLoginID
        do shell script "chown -R " & idnet & " /Users/" & netLoginID user name localAdminUser password localAdminPW with administrator privileges

        
        # create the plist file:
        do shell script "echo '<?xml version=\"1.0\" encoding=\"UTF-8\"?>' >/tmp/fvenable.plist"
        do shell script "echo '<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">' >>/tmp/fvenable.plist"
        do shell script "echo '<plist version=\"1.0\">' >>/tmp/fvenable.plist"
        do shell script "echo '<dict>' >>/tmp/fvenable.plist"
        do shell script "echo '<key>Username</key>' >>/tmp/fvenable.plist"
        do shell script "echo '<string>'" & localAdminUser & "'</string>' >>/tmp/fvenable.plist"
        do shell script "echo '<key>Password</key>' >>/tmp/fvenable.plist"
        do shell script "echo '<string>'" & localAdminPW & "'</string>' >>/tmp/fvenable.plist"
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
        try
            do shell script "fdesetup add -i < /tmp/fvenable.plist" user name localAdminUser password localAdminPW with administrator privileges
            do shell script "cp /tmp/fvenable.plist /Library/fvenable." & netLoginID & ".plist" user name localAdminUser password localAdminPW with administrator privileges
            log "FileVault enabled for " & netLoginID
        on error
            display dialog "Filevault could not add " & netLoginID & " to authorized users." buttons "OK" default button 1 with icon 2
            log "couldn't enable FileVault!"
        end try

    end addToFileVault_

end script

















