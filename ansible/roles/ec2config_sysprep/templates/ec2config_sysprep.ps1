#jinja2: newline_sequence:'\r\n'
# --------------------------------------------------------------------------------------------------#
# Sysprep a configured instance
# --------------------------------------------------------------------------------------------------#
Try
{
    $SysPrepTempPath = "{{sysprep_temp_path}}"
    $EC2ConfigBundleFilePath = "{{ec2config_bundle_file_path}}"
    $EC2ConfigSettingsFilePath = "{{ec2config_settings_file_path}}"
    $EC2ConfigSysprepFilePath ="{{ec2config_sysprep_file_path}}"
    $EC2ConfigSetPassword = "{{ec2config_set_password}}"
    $EC2ConfigHandleUserData = "{{ec2config_handle_userdata}}"
    $EC2ConfigSetComputerName = "{{ec2config_set_computer_name}}"
    $EC2ConfigDynamicBootVolumeSize = "{{ec2config_dynamic_boot_volume_size}}"
    $EC2ConfigEventLog = "{{ec2config_event_log}}"
    $EC2ConfigProcessPath = "{{ec2config_process_path}}"
    $EC2ConfigProcessArguments = "{{ec2config_process_arguments}}"
    $EC2ConfigStaticPassword = "{{sysprep_static_password}}"

    $LogFilePath = "$SysPrepTempPath/logs/ec2config_sysprep.log"
    New-Item -ItemType Directory -Force -Path "$SysPrepTempPath/logs"
    Start-Transcript -Path "$LogFilePath" -Append -Force

    $xml = [System.Xml.XmlDocument](Get-Content "$EC2ConfigBundleFilePath")
    $xmlElement = $xml.get_DocumentElement()

    foreach ($element in $xmlElement.Property){
        if ($element.Name -eq "AutoSysprep"){
            $element.Value="No"
        }elseif($element.Name -eq "SetRDPCertificate"){
            $element.Value="No"
        }elseif($element.Name -eq "SetPasswordAfterSysprep"){
            $element.Value="No"
        }
    }
    $xml.Save($EC2ConfigBundleFilePath)

    Write-Output "Successfully saved changes to the EC2 Service bundle config file."

    $xml = [System.Xml.XmlDocument](Get-Content "$EC2ConfigSettingsFilePath")
    $xmlElement = $xml.get_DocumentElement()
    $xmlElementToModify = $xmlElement.Plugins

    foreach ($element in $xmlElementToModify.Plugin){
        if ($element.name -eq "Ec2SetPassword"){
            Write-Output "Setting 'Ec2SetPassword' to '$EC2ConfigSetPassword'."
            $element.State="$EC2ConfigSetPassword"
        }elseif($element.name -eq "Ec2HandleUserData"){
            Write-Output "Setting 'Ec2HandleUserData' to '$EC2ConfigHandleUserData'."
            $element.State="$EC2ConfigHandleUserData"
        }elseif($element.name -eq "Ec2SetComputerName"){
            Write-Output "Setting 'Ec2SetComputerName' to '$EC2ConfigSetComputerName'."
            $element.State="$EC2ConfigSetComputerName"
        }elseif($element.name -eq "Ec2DynamicBootVolumeSize"){
            Write-Output "Setting 'Ec2DynamicBootVolumeSize' to '$EC2ConfigDynamicBootVolumeSize'."
            $element.State="$EC2ConfigDynamicBootVolumeSize"
        }elseif($element.name -eq "Ec2EventLog"){
            Write-Output "Setting 'Ec2EventLog' to '$EC2ConfigEventLog'."
            $element.State="$EC2ConfigEventLog"
        }
    }
    $xml.Save($EC2ConfigSettingsFilePath)

    Write-Output "Successfully saved changes to the EC2 Service settings config file."

    $xml = [System.Xml.XmlDocument](Get-Content "$EC2ConfigSysprepFilePath")

    $xmlOobeSystemShellSetup = $($xml.unattend.settings | Where-Object {$_.pass -eq "oobeSystem"}).component | Where-Object {$_.name -eq "Microsoft-Windows-Shell-Setup"}
    if( $xmlOobeSystemShellSetup ){
        $UserAccounts = $xmlOobeSystemShellSetup.ChildNodes | Where-Object {$_.Name -eq "UserAccounts"}
        if( ! $UserAccounts ){
            $UserAccounts = $xml.CreateElement("UserAccounts", $xmlOobeSystemShellSetup.NamespaceURI)
            $xmlOobeSystemShellSetup.AppendChild($UserAccounts);
        }

        $AdminPassword = $UserAccounts.ChildNodes | Where-Object {$_.Name -eq "AdministratorPassword"}
        if( ! $AdminPassword ){
            $AdminPassword = $xml.CreateElement("AdministratorPassword", $UserAccounts.NamespaceURI)
            $APValueElement = $AdminPassword.AppendChild($xml.CreateElement("Value", $AdminPassword.NamespaceURI));
            $APPlainTextElement = $AdminPassword.AppendChild($xml.CreateElement("PlainText", $AdminPassword.NamespaceURI));
            $UserAccounts.AppendChild($AdminPassword)
        }
        Write-Output "Setting static admin password."
        $AdminPassword.Value = "$EC2ConfigStaticPassword"
        $AdminPassword.PlainText = "True"
    }else{
        Throw "Failed to locate the OOBE Shell Setup component in '$EC2ConfigSysprepFilePath'."
    }

    $xml.Save($EC2ConfigSysprepFilePath)

    Write-Output "Successfully saved changes to the SysPrep config file."

    $task_name = "SysPrepShutdownTask_{0}" -f $(Get-Date -f MM-dd-yyyy_HH_mm_ss)
    $task_start_time = [datetime]::Now.AddSeconds(10)
    $task_action = New-ScheduledTaskAction -Execute "$EC2ConfigProcessPath" -Argument "$EC2ConfigProcessArguments"
    $task_trigger = New-ScheduledTaskTrigger -At $task_start_time -Once
    $task_principal = New-ScheduledTaskPrincipal -UserId Administrator -LogonType S4U -RunLevel Highest
    $task_settings = New-ScheduledTaskSettingsSet -DisallowHardTerminate -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -Priority 7
    $task_input_object = New-ScheduledTask -Action $task_action -Trigger $task_trigger -Principal $task_principal -Settings $task_settings

    Register-ScheduledTask -TaskName $task_name -InputObject $task_input_object -Force

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
