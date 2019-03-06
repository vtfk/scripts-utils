param(
    [string]$searchUsername
)

Do {

    # AD connection check
    $adModule = $true
    $adConnection = $false
    try {Import-Module activedirectory -ErrorAction stop} catch {$adModule = $false}
    if ($adModule -and @("DC=login,DC=top,DC=no") -contains (Get-ADDomain).DistinguishedName) {
        $adConnection = $true
    }
    ###

    # Formatting of AD connection status string
    $lengthOfLogo = 56
    $adConnectionString = 
    "## AD Connection: " +
    $(if ($adConnection) {"Connected"}else {"Disconnected"})

    $adConnectionString = 
    $adConnectionString + 
    (" " * ($lengthOfLogo - $adConnectionString.Length - 2)) +
    "##"
    ###

    # TODO: Find a more modular way to get the version automatically.
    # $version = $((Get-Item .\CitrixLogOff.exe).VersionInfo.FileVersion)
    $version = "1.7.6"

    Write-Output (
        "#######################  V$($version)  #######################
##        _____ _____ ___________ _______   __        ##
##       /  __ \_   _|_   _| ___ \_   _\ \ / /        ##
##       | /  \/ | |   | | | |_/ / | |  \ V /         ##
##       | |     | |   | | |    /  | |  /   \         ##
##       | \__/\_| |_  | | | |\ \ _| |_/ /^\ \        ##
##        \____/\___/  \_/ \_| \_|\___/\/   \/        ##
##  _   _ ___ ___ ___   _    ___   ___  ___  ___ ___  ##
## | | | / __| __| _ \ | |  / _ \ / __|/ _ \| __| __| ##
## | |_| \__ \ _||   / | |_| (_) | (_ | (_) | _|| _|  ##
##  \___/|___/___|_|_\ |____\___/ \___|\___/|_| |_|   ##
##                                                    ##
########################################################
$adConnectionString
########################################################")



    ######## PROMPTS FOR PARAMETERS ########
    if (!($searchUsername)) {
        Write-Host "TIP! Type `"!c`" to paste from clipboard."
        Write-Host "Please enter the username [exit]: " -NoNewLine
        $searchUsername = $Host.UI.ReadLine()
        if (!($searchUsername)) {
            Exit
        }
        Write-Output("")
    }
    ########################################

    if ($searchUsername -eq "!c") {
        try {
            $searchUsername = Get-Clipboard
            if (!$searchUsername) {
                throw "Clipboard empty"
            }
            Write-Output("Using `"$searchUsername`" from clipboard...")
            Write-Output("")
        }
        catch {
            Write-Output("Clipboard empty!")
            Read-Host -Prompt "Press 'Enter' to restart script or CTRL + C to exit..."
            # Prepare for rerun
            Clear-Host
            $searchUsername = ""
            continue
        }
    }

    function Get-ADDetailsFromUsername {
        param (
            [string]$username
        )
        if ($adConnection) {
            $user = (Get-ADUser $username -Properties Title, Department, Company | Select-Object Name, Company, Department, Title)
        }
        return $user
    }


    function progressBar {
        param (
            [double]$progress
        )

        $LengthOfBar = 20
        $progDone = $LengthOfBar * $progress
        $progLeft = $LengthOfBar * (1 - $progress)
        [int]$progPercentDone = $progress * 100

        $progressBarString = (
            "|" + 
            ("#" * $progDone) + 
            ("-" * $progLeft) +
            "| " + $progPercentDone + "%" + " |"
        )
        if ($progPercentDone -eq 100) {
            $progressBarString = $progressBarString + "`n"
        }

        return $progressBarString
    }

    function Get-QueryUserDetails {
        param(
            [string]$server
        )

        $sessionCmd = [scriptblock]::Create("(query session /Server:$server)")

        $job = Start-Job -ScriptBlock $sessionCmd
        Wait-Job -Timeout 10 $job > $nul
        $queryResult = Receive-Job $job 2>$nul
        Stop-Job $job
        Remove-Job $job

        $errorsInParser = @()
        $usersParsed = @()
        foreach ($user in $queryResult) {
            $userArr = $user.split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
            $userDetails = @("Error") * 3
        
            # Structure:
            # $userDetails[0] - Name
            # $userDetails[1] - UID
            # $userDetails[2] - Status
        
            switch ($userArr.Length) {
                # Column Titles
                6 {
                    if ($userArr -contains @("SESSIONNAME", "USERNAME")) {break}
                }

                # Active
                5 {
                    if ($userArr[3] -eq "Active") {
                        $userDetails[0] = $userArr[1]
                        $userDetails[1] = $userArr[2]
                        $userDetails[2] = $userArr[3]
                    }
                    break
                }
                # Local users
                4 {
                    if (@("console", ">console") -contains $userArr[0]) {
                        $userDetails[0] = $userArr[1]
                        $userDetails[1] = $userArr[2]
                        $userDetails[2] = $userArr[3]
                    }
                    break
                }
                # Disc / Listen
                3 {
                    if ($userArr[2] -eq "Listen") {} # Do not include Listen sessions
                    elseif ($userArr[0] -eq "services") {}
                    elseif ($userArr[2] -eq "Disc") {
                        # Disconnected, but logged on users
                        $userDetails[0] = $userArr[0]
                        $userDetails[1] = $userArr[1]
                        $userDetails[2] = $userArr[2]
                    }
                    break
                }
                # Down state (failed to initialize)
                2 {
                    if ($userArr[1] -eq "Down") {} # Do not include
                }
                default {
                    # No indentation in multiline strings
                    # %0D%0A == Newline in mail
                    $errorsInParser += (
                        "Could not parse query session output, unexpected input.%0D%0A`n" +
                        "Error occurred with this data:%0D%0A`n" +
                        "Server: $server%0D%0A`n" +
                        "########%0D%0A`n" +
                        "$userArr%0D%0A`n" +
                        "########%0D%0A`n" +
                        "$queryResult%0D%0A`n" +
                        "%0D%0A"
                    )
                    break
                }
            }
            # If user parsing was successful, append to object
            if (!($userDetails -contains "Error")) {
                $userObject = [PSCustomObject]@{
                    Username = $userDetails[0]
                    UID      = $userDetails[1]
                    Status   = $userDetails[2]
                }
                $usersParsed += $userObject
            }
        }

        return @($usersParsed, $errorsInParser)
    }

    # Returns all servers user has a session on
    function Get-UserSessions {
        param (
            [string]$username,
            [array]$servers
        )
        $serversSearched = 0
        $userSessions = @()
        $parsingErrors = @()
        foreach ($xaServer in $servers) {
            # First index: User session
            # Second index: Errors in parsing
            $getQueryResults = Get-QueryUserDetails $xaServer
    
            $user = ($getQueryResults[0] | Where-Object Username -eq $username)
            foreach ($parsingError in $getQueryResults[1]) {
                $parsingErrors += $parsingError
            }
            $serversSearched++
        
            # Write a progress bar for amount of servers searched
            write-Host("`r" + (progressBar ($serversSearched / $xaServers.Count))) -NoNewline
    
            # Add matching sessions to object
            if ($user -ne $nul) {
                $userSessions += [PSCustomObject]@{
                    Username = $username
                    Server   = $xaServer
                    UID      = $user.UID
                    Status   = $user.Status
                }
            }
        }
        return @($userSessions, $parsingErrors)
    }

    function Write-UserInfo {
        param (
            [string]$username
        )
        if ($adConnection) {
            $adDetails = Get-ADDetailsFromUsername $username
            # Name,Company,Department,Title

            Write-Output (
                "##################### User details #####################`n" +
                "Name:        $($adDetails.Name)`n" +
                "Company:     $($adDetails.Company)`n" +
                "Department:  $($adDetails.Department)`n" +
                "Title:       $($adDetails.Title)`n" +
                "########################################################"
            )
        }
    }

    function LogoffUser {
        param (
            [string]$server,
            [int]$uid
        )
        if (-not($server)) { 
            Write-Warning ("User was not logged off from this session.. (Missing server)")
            break
        }
        if (-not($uid)) { 
            Write-Warning ("User was not logged off from this session.. (Missing UID)")
            break
        }
        Start-Process -NoNewWindow -FilePath "logoff" -ArgumentList "$($uid)", "/server:$($server)"
        Write-Output ("Logged off UID $($uid) from server $($server)...")
    }

    function Get-XAServers {
        $xaServers = @()
        # Range TFK-FH-XA110 -> 145
        for ($i = 110; $i -le 145; $i++) {
            $xaServers += "TFK-FH-XA$i"
        }
        return $xaServers
    }


    # Servers to parse
    $xaServers = Get-XAServers

    if ($adConnection) {
        Write-UserInfo $searchUsername | Out-Host
        Write-Output("")
        # if (!(@("y", "yes", "") -contains (Read-Host ("Is this the correct user? (y/n) [exit]")))) {
        #     exit
        # }    
    }

    $userSessions, $sessionErrors = Get-UserSessions $searchUsername $xaServers
    # Display current sessions if more than zero
    if (!($userSessions.count -le 0)) {
        Write-Output("Current sessions:")
        Write-Output($userSessions) | Out-Host
    }

    # One session, log user off
    if ($userSessions.count -le 0) {
        Write-Output("User was not found...")
    }
    elseif ($userSessions.count -eq 1) {
        if (!(@("y", "yes", "") -contains (Read-Host ("Log user off from this session? (y/n) [exit]")))) {
            exit
        } 
        Write-Output("User found, logging off...")
        LogoffUser $userSessions.Server $userSessions.UID
    }
    # Multiple sessions, ask for which or all sessions
    elseif ($userSessions.count -ge 2) {
        Write-Output ("Select which servers to log user off from.")
        [string]$indexToLogoff = Read-Host -Prompt "Input indices (1..$($userSessions.count)) separated by space, or type * for all [exit]"

        [array]$indexToLogoff = $indexToLogoff.Split(" ")
        [array]$indexToLogoffSanitized
    
        foreach ($index in $indexToLogoff) {
        
            # Break if user want to log off user from all sessions
            if ($index -eq "*") {
                $indexToLogoffSanitized = 0..($userSessions.count - 1)
                break
            }
            [int]$index = $index
            # Remove indices outside of session scope
            if (!($index -gt $userSessions.count -or $index -le 0)) {
                [array]$indexToLogoffSanitized += ($index - 1)
            }
        }

    
        foreach ($index in $indexToLogoffSanitized) {
            #Write-Output ("LogoffUser $($userSessions[$index].Server) $($userSessions[$index].UID)")
            LogoffUser $userSessions[$index].Server $userSessions[$index].UID
        }
    }

    Read-Host -Prompt "Press 'Enter' to restart script or CTRL + C to exit..."
    Clear-Host
    $searchUsername = ""
}
while ($true -or !$searchUsername)

# TODO:
# [X] Single session logout (confirm kick)
# [X] Multi session logout (kick from several or all sessions)
# [X] Only one confirmation of kick with as much info as possible
# [ ] Asynchronous server search
# [ ] Bug report (email?)
# [ ] Auto Update (github?)
# [ ] User info (append username with #)