#jinja2: newline_sequence:'\r\n'
# --------------------------------------------------------------------------------------------------#
# Prep Windows Host for EC2Config SysPrep Shutdown
# --------------------------------------------------------------------------------------------------#
Param(
      [ValidateSet("Enabled", "Disabled")] [string]$Ec2HandleUserData = "{{ec2config_handle_userdata}}",
      [ValidateSet("Enabled", "Disabled")] [string]$Ec2DynamicBootVolumeSize= "{{ec2config_dynamic_boot_volume_size}}",
      [ValidateSet("Enabled", "Disabled")] [string]$Ec2SetPassword= "{{ec2config_set_password}}",
      [ValidateSet("Enabled", "Disabled")] [string]$Ec2EventLog = "{{ec2config_event_log}}",
      [ValidateSet("Enabled", "Disabled")] [string]$AWSEC2WindowsCloudWatchPlugIn = "{{ec2config_cloudwatch_plugin}}",
      [ValidateSet("Yes", "No")] [string]$SetRDPCertificate = "{{ec2config_bundle_set_rdp_certificate}}",
      [ValidateSet("Yes", "No")] [string]$SetPasswordAfterSysprep = "{{ec2config_bundle_set_password_after_sysprep}}",
      [ValidateSet($True, $False)] [bool]$LaunchSysPrepShutdown = $True,
      [ValidateSet($True, $False)] [bool]$ScheduleSysPrepShutdownTask = $True,
      [int]$SysPrepShutdownDelay = {{sysprep_shutdown_delay_seconds}},
      [string]$EC2StaticAdminPassword = "{{sysprep_static_password}}",
      [string]$TimestampFormat = "yyyyMMdd_hh:mm:ss"
)

Function LaunchProcessAndWait
{
    Param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$StdOutPath = [IO.Path]::GetTempFileName(),
        [string]$StdErrPath = [IO.Path]::GetTempFileName(),
        [bool]$DisplayOutput = $False,
        [int[]]$SuccessCodes = @(0,259)
    )

    If( [string]::IsNullOrEmpty($StdOutPath) -And [string]::IsNullOrEmpty($StdErrPath) ){
        $LaunchProcess = (Start-Process -FilePath "$FilePath" -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru)
    }Else{
        $LaunchProcess = (Start-Process -FilePath "$FilePath" -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$StdOutPath" -RedirectStandardError "$StdErrPath")
        If( ($DisplayOutput -eq $True) -Or -Not ($SuccessCodes -contains $LaunchProcess.ExitCode)){
            Write-Output "`r`n= STDOUT ===============================================================================`r`n$(Get-Content "$StdOutPath" -Raw)`r`n========================================================================================`r`n"
            Write-Output "`r`n= STDERR ===============================================================================`r`n$(Get-Content "$StdErrPath" -Raw)`r`n========================================================================================`r`n"
        }
        #Remove-Item -LiteralPath "$StdOutPath" -Force
        #Remove-Item -LiteralPath "$StdErrPath" -Force
    }
    If( -Not ($SuccessCodes -contains $LaunchProcess.ExitCode) ){
        Throw "ERROR: Start-Process -FilePath '$FilePath' -ArgumentList '$ArgumentList' Exited with Code[$($LaunchProcess.ExitCode)].`r`n"
    }
}

Try{

    $SysPrepWatch = [system.diagnostics.stopwatch]::StartNew()

    $StepWatch = [system.diagnostics.stopwatch]::StartNew()
    Write-Output "[$(Get-Date -f "$TimestampFormat")] Perform steps for EC2Config SysPrep Shutdown."

    $WindowsLicenseChecksOut = $False

    Write-Output "   Checking our Windows License Status..."
    $WindowsLicenseStatus = ((gwmi SoftwareLicensingProduct) | Where {$_.LicenseStatus})
    If( $WindowsLicenseStatus.LicenseStatus -eq 1){
        Write-Output "     Ok, looks like our license checks out."
        $WindowsLicenseChecksOut = $True
    }Else{
        Write-Output "     D'oh!, looks like we're NOT licensed, bakery mode sysprep shutdown will not be happening."
        If( $LaunchSysPrepShutdown -eq $True ){
            Throw "     ERROR: Windows is not licensed, bakery mode sysprep shutdown would fail."
        }
    }
    Write-Output "   Done!"

    Write-Output "   Taking out the garbage..."
    $NextPath = "$env:programfiles\Amazon\Ec2ConfigService\Logs\Ec2ConfigLog.txt"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Confirm:$False -ErrorAction SilentlyContinue
    $NextPath = "$env:programfiles\Amazon\Ec2ConfigService\Scripts\UserScript.bat"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Confirm:$False -ErrorAction SilentlyContinue
    $NextPath = "$env:programfiles\Amazon\Ec2ConfigService\Scripts\UserScript.ps1"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Confirm:$False -ErrorAction SilentlyContinue
    $NextPath = "$env:windir\System32\sysprep\Panther\IE\setupact.log"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    $NextPath = "$env:windir\System32\sysprep\Panther\setupact.log"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    $NextPath = "$env:windir\System32\sysprep\Panther\setuperr.log"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    $NextPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Recent\*"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    $NextPath = "$env:USERPROFILE\AppData\Local\Temp\*.*"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    If( Test-Path "$env:USERPROFILE\AppData\Local\Temp\2" ){
        $NextPath = "$env:USERPROFILE\AppData\Local\Temp\2\*.*"; Write-Output "     Removing '$NextPath'..."
        Remove-Item -Path "$NextPath" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    }
    $NextPath = "$env:windir\Temp\*"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    $NextPath = "$env:windir\*.DMP"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Confirm:$False -ErrorAction SilentlyContinue
    $NextPath = "$env:windir\Minidump"; Write-Output "     Removing '$NextPath'..."
    Remove-Item -Path "$NextPath" -Force -Recurse -Confirm:$False -ErrorAction SilentlyContinue
    Write-Output "   Done!"

    Write-Output "   Launching the Ec2Config Service Settings process to reset the wallpaper info."
    LaunchProcessAndWait -FilePath "$env:programfiles\Amazon\Ec2ConfigService\Ec2ConfigServiceSettings.exe" -ArgumentList @("-resetwallpaper")
    Write-Output "   Done!"

    Write-Output "   Process Parameter overrides..."
    If( [string]::IsNullOrEmpty($EC2StaticAdminPassword) ){
        Write-Output "     'EC2StaticAdminPassword' is undefined so we're..."
        Write-Output "        Setting 'Ec2SetPassword' to 'Enabled'."
        $Ec2SetPassword = "Enabled"
        Write-Output "        Setting 'SetPasswordAfterSysprep' to 'Yes'."
        $SetPasswordAfterSysprep = "Yes"
    }Else{
        Write-Output "     'EC2StaticAdminPassword' is defined so we're..."
        Write-Output "        Setting 'Ec2SetPassword' to 'Disabled'."
        $Ec2SetPassword = "Disabled"
        Write-Output "        Setting 'SetPasswordAfterSysprep' to 'No'."
        $SetPasswordAfterSysprep = "No"
    }
    Write-Output "   Done!"

    Write-Output "   Updating our EC2ConfigService Settings Config...."
    $EC2SettingsConfigFile= "$env:programfiles\Amazon\Ec2ConfigService\Settings\Config.xml"
    $EC2SettingsConfigXML = [xml](Get-Content -Path "$EC2SettingsConfigFile")
    $EC2SettingsConfigXMLElement = $EC2SettingsConfigXML.get_DocumentElement()
    $XMLElementsToModify = $EC2SettingsConfigXMLElement.Plugins
    If( $XMLElementsToModify ){
        ForEach( $NextElement in $XMLElementsToModify.Plugin ){
            $NextElementName = $NextElement.Name
            Switch( $NextElementName ){
                "Ec2HandleUserData" {
                    Write-Output "     Setting '$NextElementName' to '$Ec2HandleUserData'."
                    $NextElement.State = "$Ec2HandleUserData"
                }
                "Ec2DynamicBootVolumeSize" {
                    Write-Output "     Setting '$NextElementName' to '$Ec2DynamicBootVolumeSize'."
                    $NextElement.State = "$Ec2DynamicBootVolumeSize"
                }
                "Ec2EventLog" {
                    Write-Output "     Setting '$NextElementName' to '$Ec2EventLog'."
                    $NextElement.State = "$Ec2EventLog"
                }
                "Ec2SetPassword" {
                    Write-Output "     Setting '$NextElementName' to '$Ec2SetPassword'."
                    $NextElement.State = "$Ec2SetPassword"
                }
                "AWS.EC2.Windows.CloudWatch.PlugIn" {
                    Write-Output "     Setting '$NextElementName' to '$AWSEC2WindowsCloudWatchPlugIn'."
                    $NextElement.State = "$AWSEC2WindowsCloudWatchPlugIn"
                }
            }
        }
    }Else{
        Throw "     Failed to locate the 'Plugins' element in '$EC2SettingsBundleConfigFile'."
    }
    $EC2SettingsConfigXML.Save("$EC2SettingsConfigFile")
    Write-Output "   Done!"

    Write-Output "   Updating our EC2ConfigService Settings Bundle Config...."
    $EC2SettingsBundleConfigFile = "$env:programfiles\Amazon\Ec2ConfigService\Settings\BundleConfig.xml"
    $EC2SettingsBundleConfigXML = [xml](Get-Content -Path "$EC2SettingsBundleConfigFile")
    $EC2SettingsBundleConfigXMLElement = $EC2SettingsBundleConfigXML.get_DocumentElement()
    $XMLElementsToModify = $EC2SettingsBundleConfigXMLElement.Property
    If( $XMLElementsToModify ){
        ForEach( $NextElement in $XMLElementsToModify ){
            $NextElementName = $NextElement.Name
            Switch( $NextElementName ){
                "SetRDPCertificate" {
                    Write-Output "     Setting '$NextElementName' to '$SetRDPCertificate'."
                    $NextElement.Value = "$SetRDPCertificate"
                }
                "SetPasswordAfterSysprep" {
                    Write-Output "     Setting '$NextElementName' to '$SetPasswordAfterSysprep'."
                    $NextElement.Value = "$SetPasswordAfterSysprep"
                }
            }
        }
    }Else{
        Throw "     Failed to locate the 'Property' element in '$EC2SettingsBundleConfigFile'."
    }
    $EC2SettingsBundleConfigXML.Save("$EC2SettingsBundleConfigFile")
    Write-Output "   Done!"

    Write-Output "   Updating our EC2ConfigService SysPrep Config...."
    $EC2SysPrepConfigFile = "$env:programfiles\Amazon\Ec2ConfigService\sysprep2008.xml"
    $EC2SysPrepConfigXML = [xml](Get-Content -Path "$EC2SysPrepConfigFile")
    $EC2SysPrepConfigXMLElement = $EC2SysPrepConfigXML.get_DocumentElement()
    $OOBESystemShellSetupXMLElement = $($EC2SysPrepConfigXMLElement.settings | Where-Object {$_.pass -eq "oobeSystem"}).component | Where-Object {$_.name -eq "Microsoft-Windows-Shell-Setup"}
    If( $OOBESystemShellSetupXMLElement ){
        If( -Not [string]::IsNullOrEmpty($EC2StaticAdminPassword) ){
            Write-Output "     Setting our Administrator Static Password."
            $UserAccounts = ($OOBESystemShellSetupXMLElement.ChildNodes | Where-Object {$_.Name -eq "UserAccounts"})
            If( -Not $UserAccounts ){
                Write-Output "       'UserAccounts' element didn't exist, we're creating it."
                $UserAccounts = $EC2SysPrepConfigXML.CreateElement("UserAccounts", $OOBESystemShellSetupXMLElement.NamespaceURI)
                $OOBESystemShellSetupXMLElement.AppendChild($UserAccounts) | Out-Null
            }

            $AdminPassword = $UserAccounts.ChildNodes | Where-Object {$_.Name -eq "AdministratorPassword"}
            If( -Not $AdminPassword ){
                Write-Output "       'AdministratorPassword' element didn't exist, we're creating it."
                $AdminPassword = $EC2SysPrepConfigXML.CreateElement("AdministratorPassword", $UserAccounts.NamespaceURI)
                $APValueElement = $AdminPassword.AppendChild($EC2SysPrepConfigXML.CreateElement("Value", $AdminPassword.NamespaceURI))
                $APPlainTextElement = $AdminPassword.AppendChild($EC2SysPrepConfigXML.CreateElement("PlainText", $AdminPassword.NamespaceURI))
                $UserAccounts.AppendChild($AdminPassword)  | Out-Null
            }

            If( $EC2StaticAdminPassword -ne $AdminPassword.Value ){
                $AdminPassword.Value = "$EC2StaticAdminPassword"
                $AdminPassword.PlainText = "True"
                Write-Output "       Static Administrator Password has been set!"
                $EC2SysPrepConfigXML.Save("$EC2SysPrepConfigFile")
            }Else{
                Write-Output "       Static Administrator Password was already set!"
            }
        }Else{
            Write-Output "     Nothing to do here!"
        }
    }Else{
        Throw "     Failed to locate the OOBE Shell Setup component in '$EC2SysPrepConfigFile'."
    }
    $EC2SysPrepConfigXML.Save("$EC2SysPrepConfigFile")
    Write-Output "   Done!"

    Write-Output "   Clearing out Event Logs..."
    Write-Output "     Processing 'Application' Event Logs..."
    Clear-EventLog Application -Confirm:$False
    Write-Output "     Processing 'System' Event Logs..."
    Clear-EventLog System -Confirm:$False
    Write-Output "     Processing 'Security' Event Logs..."
    Clear-EventLog Security -Confirm:$False
    Write-Output "   Done!"

    If( ($WindowsLicenseChecksOut -eq $True) -And ($LaunchSysPrepShutdown -eq $True) ){
        If( $ScheduleSysPrepShutdownTask ){
            Write-Output "   Scheduling SysPrep shutdown to occur in '$SysPrepShutdownDelay' seconds."
            $TaskName = "SysPrepShutdownTask_{0}" -f $(Get-Date -f "yyyyMMdd_hh.mm.ss")
            $TaskStartTime = [datetime]::Now.AddSeconds($SysPrepShutdownDelay)
            $TaskAction = New-ScheduledTaskAction -Execute "$env:programfiles\Amazon\Ec2ConfigService\ec2config.exe" -Argument "-sysprep"
            $TaskTrigger = New-ScheduledTaskTrigger -At $TaskStartTime -Once
            $TaskPrincipal = New-ScheduledTaskPrincipal -UserId Administrator -LogonType S4U -RunLevel Highest
            $TaskSettings = New-ScheduledTaskSettingsSet -DisallowHardTerminate -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -Priority 7
            $TaskInputObject = New-ScheduledTask -Action $TaskAction -Trigger $TaskTrigger -Principal $TaskPrincipal -Settings $TaskSettings

            $RegResult  = (Register-ScheduledTask -TaskName $TaskName -InputObject $TaskInputObject -Force)
        }Else{
            Write-Output "   Starting SysPrep shutdown..."
            Start-Process "$env:programfiles\Amazon\Ec2ConfigService\ec2config.exe" -ArgumentList -sysprep
        }
        Write-Output "   Done!"
    }
    Write-Output ("Total elapsed time {0}:{1}:{2}" -f $StepWatch.Elapsed.Hours, $StepWatch.Elapsed.Minutes, $StepWatch.Elapsed.Seconds); Write-Output ""

    Write-Output ( "[$(Get-Date -f "$TimestampFormat")] That's a wrap, EC2Config SysPrep Process for [Name='{0}', InstanceId='{1}'] succeeded in {2}:{3}:{4}!" -f $env:COMPUTERNAME, $InstanceId, $SysPrepWatch.Elapsed.Hours, $SysPrepWatch.Elapsed.Minutes, $SysPrepWatch.Elapsed.Seconds ); Write-Output ""
}Catch{
   Write-Output $_
    Exit 1
}
