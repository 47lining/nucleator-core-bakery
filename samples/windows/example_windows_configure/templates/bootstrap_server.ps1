#jinja2: newline_sequence:'\r\n'
# --------------------------------------------------------------------------------------------------#
# Bootstrap a virgin Windows 2012 instance
# --------------------------------------------------------------------------------------------------#

if ($PSVersionTable.PSVersion.Major -lt 3)
{
    Throw "PowerShell version 3 or higher is required."
}

$host_fqdn = [System.Net.Dns]::GetHostByName(($env:computerName)) | FL HostName | Out-String | %{ "{0}" -f $_.Split(':')[1].Trim() };
Write-Host "Host FQDN: '$host_fqdn'"

$instance_id = (Invoke-RestMethod 'http://169.254.169.254/latest/meta-data/instance-id').ToString()
Write-Host "Instance ID: '$instance_id'"

$instance_az = (Invoke-RestMethod 'http://169.254.169.254/latest/meta-data/placement/availability-zone').ToString()
Write-Host "Instance AZ: '$instance_az'"

$region = $instance_az.Substring(0,$instance_az.Length-1)
Write-Host "Instance Region: '$region'"

Write-Host "Windows host configured"
