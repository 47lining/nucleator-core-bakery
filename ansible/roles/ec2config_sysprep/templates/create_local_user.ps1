#jinja2: newline_sequence:'\r\n'
Try
{
    $SysPrepTempPath = "{{sysprep_temp_path}}"
    $LogFilePath = "$SysPrepTempPath/create_local_user.log"
    $UserName = "{{sysprep_user_name}}"
    $UserPassword = "{{sysprep_static_password}}"
    $UserDescription = "{{sysprep_user_description}}"
    $UserGroup = "{{sysprep_user_group}}"

    New-Item -ItemType Directory -Force -Path "$SysPrepTempPath"
    Start-Transcript -Path "$LogFilePath" -Append -Force

    $ComputerName = "$env:COMPUTERNAME"

    $ADSIComputer = [ADSI]"WinNT://$ComputerName"
    $ADSIComputerUsers = ($ADSIComputer.psbase.children | Where-Object {$_.psBase.schemaClassName -eq "User"} | Select-Object -expand Name)

    Write-Output "Check to see if our '$UserName' user exists."
    $ADSIUserExists = ($ADSIComputerUsers -contains "$UserName")
    if( ! $ADSIUserExists ){
        $User = $ADSIComputer.Create('User',$UserName)
        Write-Output "`tNope, creating user '$UserName'..."
    }else{
        $User = [ADSI]"WinNT://$ComputerName/$UserName,user"
        Write-Output "`tYep, user '$UserName' already exists!"
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
        Write-Output "`tNope, adding user '$UserName' to the '$UserGroup' group..."
    }else{
        Write-Output "`tYep, '$UserName' is already a member of the '$UserGroup' group!"
    }
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

