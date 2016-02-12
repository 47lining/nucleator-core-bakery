#jinja2: newline_sequence:'\r\n'
Try
{
    $EC2ConfigBundleFilePath = "{{ec2config_bundle_file_path}}"
    $EC2ConfigSettingsFilePath = "{{ec2config_settings_file_path}}"
    $EC2ConfigSysprepFilePath ="{{ec2config_sysprep_file_path}}"
    $EC2ConfigSetPassword = "{{ec2config_set_password}}"
    $EC2ConfigHandleUserData = "{{ec2config_handle_userdata}}"
    $EC2ConfigSetComputerName = "{{ec2config_set_computer_name}}"
    $EC2ConfigDynamicBootVolumeSize = "{{ec2config_dynamic_boot_volume_size}}"
    $EC2ConfigEventLog = "{{ec2config_event_log}}"
    $EC2ConfigCloudWatchPlugin = "{{ec2config_cloudwatch_plugin}}"
    $EC2ConfigProcessPath = "{{ec2config_process_path}}"
    $EC2ConfigProcessArguments = "{{ec2config_process_arguments}}"
    $EC2ConfigStaticPassword = "{{sysprep_static_password}}"
    $EC2ConfigBundleAutoSysprep = "{{ec2config_bundle_auto_sysprep}}"
    $EC2ConfigBundleSetRDPCertificate = "{{ec2config_bundle_set_rdp_certificate}}"
    $EC2ConfigBundleSetPasswordAfterSysprep = "{{ec2config_bundle_set_password_after_sysprep}}"
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

    $xml = [System.Xml.XmlDocument](Get-Content "$EC2ConfigBundleFilePath")
    $xmlElement = $xml.get_DocumentElement()

    Write-Output "Set our '$(split-path "$EC2ConfigBundleFilePath" -Leaf)' settings."
    foreach ($element in $xmlElement.Property){
        if ($element.Name -eq "AutoSysprep"){
            Write-Output "  - Setting 'AutoSysprep' to '$EC2ConfigBundleAutoSysprep'."
            $element.Value="$EC2ConfigBundleAutoSysprep"
        }elseif($element.Name -eq "SetRDPCertificate"){
            Write-Output "  - Setting 'SetRDPCertificate' to '$EC2ConfigBundleSetRDPCertificate'."
            $element.Value="$EC2ConfigBundleSetRDPCertificate"
        }elseif($element.Name -eq "SetPasswordAfterSysprep"){
            Write-Output "  - Setting 'SetPasswordAfterSysprep' to '$EC2ConfigBundleSetPasswordAfterSysprep'."
            $element.Value="$EC2ConfigBundleSetPasswordAfterSysprep"
        }
    }
    $xml.Save($EC2ConfigBundleFilePath)
    Write-Output "Successfully saved changes to '$EC2ConfigBundleFilePath'."

    $xml = [System.Xml.XmlDocument](Get-Content "$EC2ConfigSettingsFilePath")
    $xmlElement = $xml.get_DocumentElement()
    $xmlElementToModify = $xmlElement.Plugins

    Write-Output "Set our '$(split-path "$EC2ConfigSettingsFilePath" -Leaf)' settings."
    foreach ($element in $xmlElementToModify.Plugin){
        if ($element.name -eq "Ec2SetPassword"){
            Write-Output "  - Setting 'Ec2SetPassword' to '$EC2ConfigSetPassword'."
            $element.State="$EC2ConfigSetPassword"
        }elseif($element.name -eq "Ec2HandleUserData"){
            Write-Output "  - Setting 'Ec2HandleUserData' to '$EC2ConfigHandleUserData'."
            $element.State="$EC2ConfigHandleUserData"
        }elseif($element.name -eq "Ec2SetComputerName"){
            Write-Output "  - Setting 'Ec2SetComputerName' to '$EC2ConfigSetComputerName'."
            $element.State="$EC2ConfigSetComputerName"
        }elseif($element.name -eq "Ec2DynamicBootVolumeSize"){
            Write-Output "  - Setting 'Ec2DynamicBootVolumeSize' to '$EC2ConfigDynamicBootVolumeSize'."
            $element.State="$EC2ConfigDynamicBootVolumeSize"
        }elseif($element.name -eq "Ec2EventLog"){
            Write-Output "  - Setting 'Ec2EventLog' to '$EC2ConfigEventLog'."
            $element.State="$EC2ConfigEventLog"
        }elseif($element.name -eq "AWS.EC2.Windows.CloudWatch.PlugIn"){
            Write-Output "  - Setting 'AWS.EC2.Windows.CloudWatch.PlugIn' to '$EC2ConfigCloudWatchPlugin'."
            $element.State="$EC2ConfigCloudWatchPlugin"
        }
    }
    $xml.Save($EC2ConfigSettingsFilePath)
    Write-Output "Successfully saved changes to '$EC2ConfigSettingsFilePath'."

    $xml = [System.Xml.XmlDocument](Get-Content "$EC2ConfigSysprepFilePath")

    Write-Output "Set our '$(split-path "$EC2ConfigSysprepFilePath" -Leaf)' settings."
    $xmlOobeSystemShellSetup = $($xml.unattend.settings | Where-Object {$_.pass -eq "oobeSystem"}).component | Where-Object {$_.name -eq "Microsoft-Windows-Shell-Setup"}
    if( $xmlOobeSystemShellSetup ){
        $UserAccounts = $xmlOobeSystemShellSetup.ChildNodes | Where-Object {$_.Name -eq "UserAccounts"}
        if( ! $UserAccounts ){
            Write-Output "  - UserAccounts element didn't exist, we're creating it."
            $UserAccounts = $xml.CreateElement("UserAccounts", $xmlOobeSystemShellSetup.NamespaceURI)
            $xmlOobeSystemShellSetup.AppendChild($UserAccounts);
        }

        $AdminPassword = $UserAccounts.ChildNodes | Where-Object {$_.Name -eq "AdministratorPassword"}
        if( ! $AdminPassword ){
            Write-Output "  - AdministratorPassword element didn't exist, we're creating it."
            $AdminPassword = $xml.CreateElement("AdministratorPassword", $UserAccounts.NamespaceURI)
            $APValueElement = $AdminPassword.AppendChild($xml.CreateElement("Value", $AdminPassword.NamespaceURI));
            $APPlainTextElement = $AdminPassword.AppendChild($xml.CreateElement("PlainText", $AdminPassword.NamespaceURI));
            $UserAccounts.AppendChild($AdminPassword)
        }
        Write-Output "  - Setting our static Administrator password."
        $AdminPassword.Value = "$EC2ConfigStaticPassword"
        $AdminPassword.PlainText = "True"
    }else{
        Throw "Failed to locate the OOBE Shell Setup component in '$EC2ConfigSysprepFilePath'."
    }

    $xml.Save($EC2ConfigSysprepFilePath)
    Write-Output "Successfully saved changes to '$EC2ConfigSysprepFilePath'."

    Write-Output "Scheduling SysPrep shutdown to occur in 10 seconds."
    $task_name = "SysPrepShutdownTask_{0}" -f $(Get-Date -f MM-dd-yyyy_HH_mm_ss)
    $task_start_time = [datetime]::Now.AddSeconds(10)
    $task_action = New-ScheduledTaskAction -Execute "$EC2ConfigProcessPath" -Argument "$EC2ConfigProcessArguments"
    $task_trigger = New-ScheduledTaskTrigger -At $task_start_time -Once
    $task_principal = New-ScheduledTaskPrincipal -UserId Administrator -LogonType S4U -RunLevel Highest
    $task_settings = New-ScheduledTaskSettingsSet -DisallowHardTerminate -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -Priority 7
    $task_input_object = New-ScheduledTask -Action $task_action -Trigger $task_trigger -Principal $task_principal -Settings $task_settings

    Register-ScheduledTask -TaskName $task_name -InputObject $task_input_object -Force

    Write-Output "Successfully scheduled our sysprep shutdown task, that's a wrap!"

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
