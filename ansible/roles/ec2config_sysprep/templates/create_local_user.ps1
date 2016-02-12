#jinja2: newline_sequence:'\r\n'
# --------------------------------------------------------------------------------------------------#
# Create a local devops user
# --------------------------------------------------------------------------------------------------#
Try
{
    $UserName = "{{sysprep_user_name}}"
    $UserPassword = "{{sysprep_static_password}}"
    $UserDescription = "{{sysprep_user_description}}"
    $UserGroup = "{{sysprep_user_group}}"
    $DevOpsBaseFolder = "{{sysprep_devops_base_folder}}"

    $CurrentDrive = $pwd.Drive.Name.ToLower()
    $DevOpsBaseFolderPath = "{0}:/{1}" -f $CurrentDrive, $DevOpsBaseFolder
    $DevOpsLogsPath = "$DevOpsBaseFolderPath/logs"
    if( -Not ( Test-Path -Path "$DevOpsLogsPath" ) ){
        $LogsFolder = New-Item -Path "$DevOpsLogsPath" -Type Directory
    }

    $TranscriptFileName = "{0}_{1}.log" -f $MyInvocation.MyCommand.Name.Replace(".","_"), $(Get-Date -f MM-dd-yyyy_HH_mm_ss)
    $TranscriptFilePath = "{0}/{1}" -f $DevOpsLogsPath, $TranscriptFileName
    Start-Transcript -Path "$TranscriptFilePath" -NoClobber

    $ComputerName = "$env:COMPUTERNAME"

    $ADSIComputer = [ADSI]"WinNT://$ComputerName"
    $ADSIComputerUsers = ($ADSIComputer.psbase.children | Where-Object {$_.psBase.schemaClassName -eq "User"} | Select-Object -expand Name)

    Write-Output "Check to see if our '$UserName' user exists."
    $ADSIUserExists = ($ADSIComputerUsers -contains "$UserName")
    if( ! $ADSIUserExists ){
        $User = $ADSIComputer.Create('User',$UserName)
        Write-Output "  - No, creating user '$UserName'..."
    }else{
        $User = [ADSI]"WinNT://$ComputerName/$UserName,user"
        Write-Output "  - Yes, user '$UserName' already exists!"
    }

    $User.SetPassword($UserPassword)
    $User.SetInfo()
    $User.Description = "$UserDescription"
    $User.SetInfo()

    $ADSIUserGroups = ($User.psbase.Invoke("groups") | foreach {$_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)})

    Write-Output "Check to see if our '$UserName' user is in the '$UserGroup' group."
    $ADSIUserIsInGroup = ($ADSIUserGroups -contains "$UserGroup")
    if( ! $ADSIUserIsInGroup ){
        $ADSIUserGroup = [ADSI]"WinNT://$ComputerName/$UserGroup,group"
        $ADSIUserGroup.Add($User.Path)
        Write-Output "  - No, adding user '$UserName' to the '$UserGroup' group..."
    }else{
        Write-Output "  - Yes, '$UserName' is already a member of the '$UserGroup' group!"
    }

    Write-Output "That's a wrap!"
}
Catch
{
    Write-Output $_
    Exit 1
}
Finally
{
    Stop-Transcript
}

