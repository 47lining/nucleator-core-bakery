#jinja2: newline_sequence:'\r\n'
# --------------------------------------------------------------------------------------------------#
# Sysprep a configured instance
# --------------------------------------------------------------------------------------------------#

Param(
    [string]$EC2ConfigSettingsFilePath = "{{ec2config_settings_file_path}}",
    [string]$EC2ConfigSetPassword = "{{ec2config_set_password}}",
    [string]$EC2ConfigHandleUserData = "{{ec2config_handle_userdata}}",
    [string]$EC2ConfigSetComputerName = "{{ec2config_set_computer_name}}",
    [string]$SysPrepFilePath = "{{sysprep_file_path}}",
    [string]$SysPrepProcessPath = "{{sysprep_process_path}}",
    [string]$SysPrepProcessArguments = "{{sysprep_process_arguments}}",
    [string]$SysPrepStaticPassword = "{{sysprep_static_password}}"
)

Trap
{
    $_
    Exit 1
}
$ErrorActionPreference = "Stop"


$xml = [System.Xml.XmlDocument](Get-Content $EC2ConfigSettingsFilePath)
$xmlElement = $xml.get_DocumentElement()
$xmlElementToModify = $xmlElement.Plugins

foreach ($element in $xmlElementToModify.Plugin){
    if ($element.name -eq "Ec2SetPassword"){
        Write-Host "Setting 'Ec2SetPassword' to '$EC2ConfigSetPassword'."
        $element.State="$EC2ConfigSetPassword"
    }elseif($element.name -eq "Ec2HandleUserData"){
        Write-Host "Setting 'Ec2HandleUserData' to '$EC2ConfigHandleUserData'."
        $element.State="$EC2ConfigHandleUserData"
    }elseif($element.name -eq "Ec2SetComputerName"){
        Write-Host "Setting 'Ec2SetComputerName' to '$EC2ConfigSetComputerName'."
        $element.State="$EC2ConfigSetComputerName"
    }
}
$xml.Save($EC2ConfigSettingsFilePath)

Write-Host "Successfully saved changes to the EC2 Service settings config file."

$xml = [System.Xml.XmlDocument](Get-Content $SysPrepFilePath)
$xmlElement = $xml.get_DocumentElement()
$xmlElementToModify = $xmlElement.settings

foreach( $element in $xml.unattend.settings.component ){
    if( $element.name -eq "Microsoft-Windows-Shell-Setup" ){
        $UserAccounts = $element.SelectSingleNode("./UserAccounts")
        if( $UserAccounts ){
            $AdminPassword = $UserAccounts.SelectSingleNode("./AdministratorPassword")
            if( ! $AdminPassword ){
                $AdminPassword = $xml.CreateElement("AdministratorPassword")
                $APValueElement = $AdminPassword.AppendChild($xml.CreateElement("Value"));
                $APPlainTextElement = $AdminPassword.AppendChild($xml.CreateElement("PlainText"));
                $UserAccounts.AppendChild($AdminPassword)
            }
            Write-Host "Setting static admin password."
            $AdminPassword.Value = "$SysPrepStaticPassword"
            $AdminPassword.PlainText = "True"
            break
        }
    }
}
$xml.Save($SysPrepFilePath)

Write-Host "Successfully saved changes to the SysPrep config file."

$task_name = "SysPrepShutdownTask_{0}" -f $(Get-Date -f MM-dd-yyyy_HH_mm_ss)
$task_start_time = [datetime]::Now.AddSeconds(10)
$task_action = New-ScheduledTaskAction -Execute "$SysPrepProcessPath" -Argument "$SysPrepProcessArguments"
$task_trigger = New-ScheduledTaskTrigger -At $task_start_time -Once
$task_principal = New-ScheduledTaskPrincipal -UserId Administrator -LogonType S4U -RunLevel Highest
$task_settings = New-ScheduledTaskSettingsSet -DisallowHardTerminate -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -Priority 7
$task_input_object = New-ScheduledTask -Action $task_action -Trigger $task_trigger -Principal $task_principal -Settings $task_settings

Register-ScheduledTask -TaskName $task_name -InputObject $task_input_object -Force
