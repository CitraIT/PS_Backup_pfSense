<#
# CITRA IT - EXCELÊNCIA EM TI
# SCRIPT PARA BACKUP DO FIREWALL PFSENSE VIA EXPORT
# AUTOR: luciano@citrait.com.br
# DATA: 01/10/2021
# EXAMPLO DE USO: Powershell -ExecutionPolicy ByPass -File C:\scripts\PS_Backup_pfSense_Configuration.ps1

# Importante! A senha deve ser inserida como codificada em base64

#>

# 
############ USER PARAMETERS ############
$destination = "$pwd"
$server = "192.168.1.1"
$user = "admin"
$password = "cGZzZW5zZQ=="  # "pfsense" as base64 encoded
$UseSSL = $True


############ DO NOT MODIFY BELLOW ############

#
# Enable accepting self signed certificates
#
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
	public bool CheckValidationResult (
	ServicePoint srvPoint, X509Certificate certificate,
	WebRequest request, int certificateProblem) {
		return true;
	}	

}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy




#
# Preferences
#
$DebugPreference = "Continue"



#
# path to save the backup file
#
Write-Debug "Salvando o backup do pfSense na pasta: $destination"



#
# HTTP Schema
#
If($UseSSL)
{
    $schema = "https://"
}else{
    $schema = "http://"
}



#
# base uri
#
$baseuri   = $schema + $server
$backupuri = $baseuri + "/diag_backup.php"


Write-Debug "base uri: $baseuri"
Write-Debug "backup uri: $backupuri"



#
# Initial request to landing page
#
try{
    $req = invoke-webrequest -Uri $baseuri -Method GET -SessionVariable 'websess' -UseBasicParsing
}catch{
    Write-Error "Error requesting initial landing page."
    Throw $_
}


# Filling login formdata
$logindata = @{
	usernamefld  = $user;
	passwordfld  = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($password));
	login        = "Sign+In";
	__csrf_magic = $req.InputFields.FindByName("__csrf_magic").Value
}



#
# Sending login form
#
try{
    $req = invoke-webrequest -Uri $baseuri -Method POST `
        -WebSession $websess -Body $logindata -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing
}catch{
    Write-Error "Error sending login form data."
    Throw $_
}



#
# Extracting last _csrf token
#
$token = $req.InputFields.FindByName("__csrf_magic").Value
Write-Debug "extracted _csrc token: $token"


# Request backup file
try{
    $req = Invoke-WebRequest -Uri $backupuri -Method POST -UseBasicParsing `
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
    [System.Text.Encoding]::UTF8.GetString($req.Content) | Out-File -FilePath $filepath -Encoding utf8
}catch{
    Write-Error "Error saving backup file. Please check if you have write access to destionation folder."
    Throw $_
}
