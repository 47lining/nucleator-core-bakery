#jinja2: newline_sequence:'\r\n'
Try
{
    $LogFilePath = "{{sysprep_log_file_path}}/create_local_user.log"
    $UserName = "{{sysprep_user_name}}"
    $UserPassword = "{{sysprep_static_password}}"
    $UserDescription = "{{sysprep_user_description}}"
    $UserGroup = "{{sysprep_user_group}}"

    New-Item -ItemType Directory -Force -Path "{{sysprep_log_file_path}}"
    Start-Transcript -Path "$LogFilePath" -Append -Force

    $ADSIComputer = [ADSI]"WinNT://$env:COMPUTERNAME"
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

    $SecurePassword = ConvertTo-SecureString "$UserPassword" -AsPlainText -Force
    $BSTRPassword = [system.runtime.interopservices.marshal]::SecureStringToBSTR($SecurePassword)
    $_SecurePassword = [system.runtime.interopservices.marshal]::PtrToStringAuto($BSTRPassword)
    $User.SetPassword(($_SecurePassword))
    $User.SetInfo()
    $User.Description = "$UserDescription"
    $User.SetInfo()

    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTRPassword)
    Remove-Variable SecurePassword,BSTRPassword,_SecurePassword

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
}
Finally
{
    Stop-Transcript
}

