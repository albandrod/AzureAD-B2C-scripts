param (
    [Parameter(Mandatory=$false)][Alias('p')][string]$PolicyPath = "",    
    [Parameter(Mandatory=$false)][Alias('r')][string]$RelyingPartyFileName = "SignUpOrSignin.xml",
    [Parameter(Mandatory=$false)][Alias('d')][boolean]$DownloadHtmlTemplates = $false,    
    [Parameter(Mandatory=$false)][Alias('u')][string]$urlBaseUx = "",
    [Parameter(Mandatory=$false)][Alias('v')][string]$Version = "1.2.0"
    )

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

function DownloadFile ( $Url, $LocalPath ) {
    $p = $Url -split("/")
    $filename = $p[$p.Length-1]
    $LocalFile = "$LocalPath\$filename"
    Write-Host "Downloading $Url to $LocalFile"
    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($Url,$LocalFile)
}
    
if ( "" -eq $PolicyPath ) {
    $PolicyPath = (get-location).Path
}
    
[xml]$base =Get-Content -Path "$PolicyPath\TrustFrameworkBase.xml" -Raw
[xml]$ext =Get-Content -Path "$PolicyPath\TrustFrameworkExtensions.xml" -Raw

$tenantShortName = $base.TrustFrameworkPolicy.TenantId.Split(".")[0]
$cdefs = $base.TrustFrameworkPolicy.BuildingBlocks.ContentDefinitions.Clone()

if ( $true -eq $DownloadHtmlTemplates) {    
    $ret = New-Item -Path $PolicyPath -Name "html" -ItemType "directory" -ErrorAction SilentlyContinue
}
<##>
foreach( $contDef in $cdefs.ContentDefinition ) {    
    switch( $contDef.DataUri ) {        
        "urn:com:microsoft:aad:b2c:elements:globalexception:1.0.0" { $contDef.DataUri = "urn:com:microsoft:aad:b2c:elements:contract:globalexception:$Version" } 
        "urn:com:microsoft:aad:b2c:elements:globalexception:1.1.0" { $contDef.DataUri = "urn:com:microsoft:aad:b2c:elements:contract:globalexception:$Version" }
        "urn:com:microsoft:aad:b2c:elements:idpselection:1.0.0"    { $contDef.DataUri = "urn:com:microsoft:aad:b2c:elements:contract:providerselection:$Version" }
        "urn:com:microsoft:aad:b2c:elements:multifactor:1.0.0"     { $contDef.DataUri = "urn:com:microsoft:aad:b2c:elements:contract:multifactor:$Version" }
        "urn:com:microsoft:aad:b2c:elements:multifactor:1.1.0"     { $contDef.DataUri = "urn:com:microsoft:aad:b2c:elements:contract:multifactor:$Version" }

        "urn:com:microsoft:aad:b2c:elements:unifiedssd:1.0.0"    { $contDef.DataUri = "urn:com:microsoft:aad:b2c:elements:contract:unifiedssd:$Version" } 
        "urn:com:microsoft:aad:b2c:elements:unifiedssp:1.0.0"    { $contDef.DataUri = "urn:com:microsoft:aad:b2c:elements:contract:unifiedssp:$Version" } 

        "urn:com:microsoft:aad:b2c:elements:selfasserted:1.0.0"    { $contDef.DataUri = "urn:com:microsoft:aad:b2c:elements:contract:selfasserted:$Version" } 
        "urn:com:microsoft:aad:b2c:elements:selfasserted:1.1.0"    { $contDef.DataUri = "urn:com:microsoft:aad:b2c:elements:contract:selfasserted:$Version" }
    }  
    if ( $true -eq $DownloadHtmlTemplates) {
        $url = "https://$tenantShortName.b2clogin.com/static" + $contDef.LoadUri.Replace("~", "")
        DownloadFile $url "$PolicyPath\html"
    }
    if ( "" -ne $urlBaseUx ) {
        $p = $contDef.LoadUri -split("/")
        $filename = $p[$p.Length-1]
        $contDef.LoadUri = "$urlBaseUx/$filename"
    }
}

<##>
$ext.TrustFrameworkPolicy.InnerXml = $ext.TrustFrameworkPolicy.InnerXml.Replace("</BuildingBlocks>", "<ContentDefinitions>" + $cdefs.InnerXml + "</ContentDefinitions></BuildingBlocks>")
$ext.Save("$PolicyPath\TrustFrameworkExtensions.xml")

<##>
if ( "" -ne $RelyingPartyFileName ) {
    [xml]$rp =Get-Content -Path "$PolicyPath\$RelyingPartyFileName" -Raw
    $rp.TrustFrameworkPolicy.RelyingParty.InnerXml = $rp.TrustFrameworkPolicy.RelyingParty.InnerXml.Replace("<TechnicalProfile", "<UserJourneyBehaviors><ScriptExecution>Allow</ScriptExecution></UserJourneyBehaviors><TechnicalProfile")
    $rp.Save("$PolicyPath\$RelyingPartyFileName")
}
<##>