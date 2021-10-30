<#
# CITRA IT - EXCELÊNCIA EM TI
# SCRIPT PARA BACKUP DO FIREWALL PFSENSE VIA BACKUP EXPORT
# AUTOR: luciano@citrait.com.br
# DATA: 01/10/2021
# Homologado para executar no Windows 10 ou Server 2012R2+
# EXAMPLO DE USO: Powershell -ExecutionPolicy ByPass -File C:\scripts\PS_Backup_pfSense_Configuration.ps1

# Importante! A senha deve ser inserida como codificada em base64

#>
#Requires –Version 4
Param(
	[Switch]$Debug=$False
)
If($Debug){ $DebugPreference = "Continue" }


 
############ USER PARAMETERS ############
$destination = "$pwd"
$server = "192.168.1.1"
$user = "admin"
$password = "UDRzc3dvcmQ=" # base64 encoded password
$UseSSL = $True



############ DO NOT MODIFY FROM NOW ON UNLESS YOU ARE A PS EXPERT ############
############     DON'T TELL I DIDN'T WARN YOU :D      ############



#
# Função para logging na tela com timestamp
#
Function Log {
	Param([String] $text)
	
	$date = (Get-Date -Format G)
	Write-Host -ForegroundColor Green "$date $text"
}


#
# Which HTTP Schema to use
#
If($UseSSL)
{
    $schema = "https://"
}else{
    $schema = "http://"
}



#
# Building URI's
#
$pfsense_base_uri   = New-Object System.URI ($schema + $server)
$pfsense_backup_uri = New-Object System.URI ($pfsense_base_uri.AbsoluteUri + "diag_backup.php")
Write-Debug "base uri: $pfsense_base_uri"
Write-Debug "backup uri: $pfsense_backup_uri"



#
# Enable accepting self signed certificates (default pfsense webgui certificate is self signed)
# Use a custom CertificateValidationPolicy that always returns true
#
Write-Debug "Enabling trust on self-signed certificates via .net assembly"
add-type @"
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public class TrustAllCertsPolicy : ICertificatePolicy {
	public bool CheckValidationResult (
		ServicePoint srvPoint, X509Certificate certificate,
		WebRequest request, int certificateProblem) {
			return true;
	}	
}
"@
Write-Debug "Modifying the CertificateTrustPolicy"
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy



#
# Setting SSL/TLS connection to all supported versions
#
Write-Debug "Enabling all possible ssl/tls versions"
$valid_ssl_versions = [System.Net.SecurityProtocolType].getenumnames()
[system.net.servicepointmanager]::securityprotocol = $valid_ssl_versions



#
# Register the starting of the backup
#
Log "[+] Starting pfSense backup..."




#
# Initial request to landing page to get cookies and csrf token
#
Write-Debug "Requesting pfSense landing page..."
Log "[+] Validating credentials..."
try{
    $req = invoke-webrequest -Uri $pfsense_base_uri -Method GET -SessionVariable 'websess' -UseBasicParsing
	Write-Debug "Successfully retrieved landing page"
}catch{
    Write-Error "Error requesting initial landing page."
    Throw $_
}



#
# Filling login formdata
#
Write-Debug "Filling login form data"
$logindata = @{
	usernamefld  = $user;
	passwordfld  = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($password));
	login        = "Sign+In";
	__csrf_magic = $req.InputFields.FindByName("__csrf_magic").Value
}



#
# Sending login form to authentication page
#
Write-Debug "Sending login form"
try{
    $req = invoke-webrequest -Uri $pfsense_base_uri -Method POST `
        -WebSession $websess -Body $logindata -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing
	Write-Debug "Successfully logged-in into pfSense"
}catch{
    Write-Error "Error sending login form data."
    Throw $_
}



#
# Extracting last _csrf token
#
Write-Debug "Extracting _csrc token..."
$token = $req.InputFields.FindByName("__csrf_magic").Value
Write-Debug "Extracted _csrc token: $token"



#
# Request backup file
#
Write-Debug "Requesting dump of config file"
Log "[+] Downloading configutation file..."
try{
    $req = Invoke-WebRequest -Uri $pfsense_backup_uri -Method POST -UseBasicParsing `
        -ContentType 'multipart/form-data; boundary=---------------------------3203714523379' `
        -WebSession $websess -Body @"
-----------------------------3203714523379
Content-Disposition: form-data; name="__csrf_magic"

$token
-----------------------------3203714523379
Content-Disposition: form-data; name="backuparea"


-----------------------------3203714523379
Content-Disposition: form-data; name="donotbackuprrd"

yes
-----------------------------3203714523379
Content-Disposition: form-data; name="encrypt_password"


-----------------------------3203714523379
Content-Disposition: form-data; name="download"

Download configuration as XML
-----------------------------3203714523379
Content-Disposition: form-data; name="restorearea"


-----------------------------3203714523379
Content-Disposition: form-data; name="conffile"; filename=""
Content-Type: application/octet-stream


-----------------------------3203714523379
Content-Disposition: form-data; name="decrypt_password"


-----------------------------3203714523379--
"@
}catch{
    Write-Error "Error requesting backup file"
    Throw $_
}



#
# Saving the downloaded .xml file
#
try{
    $filename = $req.Headers.'content-disposition'.split(";")[1].split("=")[1]
    Write-Debug "File name got from html headers: $filename"
    $filepath = Join-Path -Path $destination -ChildPath $filename
	Write-Debug "Saving backup file to: $filepath"
    [System.Text.Encoding]::UTF8.GetString($req.Content) | Out-File -FilePath $filepath -Encoding utf8
	Log "File saved as $filepath"
	Log "[+] Backup Completed"
}catch{
    Write-Error "Error saving backup file. Please check if you have write access to destionation folder."
    Throw $_
}
