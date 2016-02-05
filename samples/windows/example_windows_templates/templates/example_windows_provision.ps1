#jinja2: newline_sequence:'\r\n'
# --------------------------------------------------------------------------------------------------#
# Provision a virgin Windows 2012 instance for use with Ansible.
# --------------------------------------------------------------------------------------------------#

Param (
    [string]$ProvisionUser="{{provision_user}}",
    [string]$ProvisionUserStaticPassword="{{provision_user_static_password}}",
    [int]$ProvisionCertValidDays={{provision_cert_valid_days}}
)

Function New-LegacySelfSignedCert
{
    Param (
        [string]$SubjectName,
        [int]$ValidDays = 365
    )

    $name = New-Object -COM "X509Enrollment.CX500DistinguishedName.1"
    $name.Encode("CN=$SubjectName", 0)

    $key = New-Object -COM "X509Enrollment.CX509PrivateKey.1"
    $key.ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
    $key.KeySpec = 1
    $key.Length = 1024
    $key.SecurityDescriptor = "D:PAI(A;;0xd01f01ff;;;SY)(A;;0xd01f01ff;;;BA)(A;;0x80120089;;;NS)"
    $key.MachineContext = 1
    $key.Create()

    $serverauthoid = New-Object -COM "X509Enrollment.CObjectId.1"
    $serverauthoid.InitializeFromValue("1.3.6.1.5.5.7.3.1")
    $ekuoids = New-Object -COM "X509Enrollment.CObjectIds.1"
    $ekuoids.Add($serverauthoid)
    $ekuext = New-Object -COM "X509Enrollment.CX509ExtensionEnhancedKeyUsage.1"
    $ekuext.InitializeEncode($ekuoids)

    $cert = New-Object -COM "X509Enrollment.CX509CertificateRequestCertificate.1"
    $cert.InitializeFromPrivateKey(2, $key, "")
    $cert.Subject = $name
    $cert.Issuer = $cert.Subject
    $cert.NotBefore = (Get-Date).AddDays(-1)
    $cert.NotAfter = $cert.NotBefore.AddDays($ValidDays)
    $cert.X509Extensions.Add($ekuext)
    $cert.Encode()

    $enrollment = New-Object -COM "X509Enrollment.CX509Enrollment.1"
    $enrollment.InitializeFromRequest($cert)
    $certdata = $enrollment.CreateRequest(0)
    $enrollment.InstallResponse(2, $certdata, 0, "")

    Get-ChildItem "Cert:\LocalMachine\my"| Sort-Object NotBefore -Descending | Select -First 1 | Select -Expand Thumbprint
}

Trap
{
    $_
    Exit 1
}
$ErrorActionPreference = "Stop"

If ($PSVersionTable.PSVersion.Major -lt 3)
{
    Throw "PowerShell version 3 or higher is required."
}

Write-Host "Setting '$ProvisionUser' fixed password"
$admin_user=[ADSI]"WinNT://$env:COMPUTERNAME/$ProvisionUser,user"
$admin_user.SetPassword("$ProvisionUserStaticPassword");
$admin_user.SetInfo();

Write-Host "Enable Remote Desktop"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0 -Force

Write-Host "Allow incoming RDP on firewall"
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

Write-Host "Enable secure RDP authentication"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1

Write-Host "Verifying WinRM service."
If (!(Get-Service "WinRM"))
{
    Throw "Unable to find the WinRM service."
}
ElseIf ((Get-Service "WinRM").Status -ne "Running")
{
    Write-Host "Starting WinRM service."
    Set-Service -Name "WinRM" -StartupType Automatic
    Start-Service -Name "WinRM" -ErrorAction Stop
}

If (!(Get-PSSessionConfiguration -Verbose:$false) -or (!(Get-ChildItem WSMan:\localhost\Listener)))
{
    Write-Host "Enabling PS Remoting."
    Enable-PSRemoting -Force -ErrorAction Stop
}
Else
{
    Write-Host "PS Remoting is already enabled."
}

# Need to think about this for sysprepped amis that might possibly have
# listeners already setup and configured with a different computer name.
winrm delete winrm/config/Listener?Address=*+Transport=HTTPS

$listeners = Get-ChildItem WSMan:\localhost\Listener
If (!($listeners | Where {$_.Keys -like "TRANSPORT=HTTPS"}))
{
    If (Get-Command "New-SelfSignedCertificate" -ErrorAction SilentlyContinue)
    {
        $cert = New-SelfSignedCertificate -DnsName "$env:COMPUTERNAME" -CertStoreLocation "Cert:\LocalMachine\My"
        $thumbprint = $cert.Thumbprint
    }
    Else
    {
        $thumbprint = New-LegacySelfSignedCert -SubjectName "$env:COMPUTERNAME" -ValidDays $ProvisionCertValidDays
    }

    $valueset = @{}
    $valueset.Add('Hostname', $env:COMPUTERNAME)
    $valueset.Add('CertificateThumbprint', $thumbprint)

    $selectorset = @{}
    $selectorset.Add('Transport', 'HTTPS')
    $selectorset.Add('Address', '*')

    Write-Host "Enabling SSL listener."
    New-WSManInstance -ResourceURI 'winrm/config/Listener' -SelectorSet $selectorset -ValueSet $valueset
}
Else
{
    Write-Host "SSL listener is already active."
}

$basicAuthSetting = Get-ChildItem WSMan:\localhost\Service\Auth | Where {$_.Name -eq "Basic"}
If (($basicAuthSetting.Value) -eq $false)
{
    Write-Host "Enabling basic auth support."
    Set-Item -Path "WSMan:\localhost\Service\Auth\Basic" -Value $true
}
Else
{
    Write-Host "Basic auth is already enabled."
}

$fwtest1 = netsh advfirewall firewall show rule name="Allow WinRM HTTPS"
$fwtest2 = netsh advfirewall firewall show rule name="Allow WinRM HTTPS" profile=any
If ($fwtest1.count -lt 5)
{
    Write-Host "Adding firewall rule to allow WinRM HTTPS."
    netsh advfirewall firewall add rule profile=any name="Allow WinRM HTTPS" dir=in localport=5986 protocol=TCP action=allow
}
ElseIf (($fwtest1.count -ge 5) -and ($fwtest2.count -lt 5))
{
    Write-Host "Updating firewall rule to allow WinRM HTTPS for any profile."
    netsh advfirewall firewall set rule name="Allow WinRM HTTPS" new profile=any
}
Else
{
    Write-Host "Firewall rule already exists to allow WinRM HTTPS."
}

$httpResult = Invoke-Command -ComputerName "localhost" -ScriptBlock {$env:COMPUTERNAME} -ErrorVariable httpError -ErrorAction SilentlyContinue

$httpsOptions = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
$httpsResult = New-PSSession -UseSSL -ComputerName "localhost" -SessionOption $httpsOptions -ErrorVariable httpsError -ErrorAction SilentlyContinue

If ($httpResult -and $httpsResult)
{
    Write-Host "HTTP and HTTPS sessions are enabled."
}
ElseIf ($httpsResult -and !$httpResult)
{
    Write-Host "HTTP sessions are disabled, HTTPS session are enabled."
}
ElseIf ($httpResult -and !$httpsResult)
{
    Write-Host "HTTPS sessions are disabled, HTTP session are enabled."
}
Else
{
    Throw "Unable to establish an HTTP or HTTPS remoting session."
}

Write-Host "PS Remoting has been successfully configured."
