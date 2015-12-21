#jinja2: newline_sequence:'\r\n'
# --------------------------------------------------------------------------------------------------#
# Sysprep a configured instance
# --------------------------------------------------------------------------------------------------#

Param(
    [string]$EC2ConfigSettingsFilePath = "{{ec2config_settings_file_path}}",
    [string]$EC2ConfigHandleUserDataState = "{{ec2config_handle_userdata_state}}",
    [string]$EC2ConfigSetComputerName = "{{ec2config_set_computer_name_state}}",
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
        $element.State="Disabled"
    }elseif($element.name -eq "Ec2HandleUserData"){
        Write-Host "Setting 'Ec2HandleUserData' to '$EC2ConfigHandleUserDataState'."
        $element.State="$EC2ConfigHandleUserDataState"
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
            $AdminPassword.Value = "$SysPrepStaticPassword"
            $AdminPassword.PlainText = "True"
            break
        }
    }
}
$xml.Save($SysPrepFilePath)

Write-Host "Successfully saved changes to the SysPrep config file."

# It's lights out for winrm comms after this process completes, instance will be in a stopped state.
Start-Process -FilePath "$SysPrepProcessPath" -ArgumentList "$SysPrepProcessArguments" -Wait

