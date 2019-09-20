param (
    [Parameter(Mandatory=$true)][Alias('p')][string]$PolicyPath = "",
    [Parameter(Mandatory=$true)][Alias('t')][string]$TenantName = "",
    [Parameter(Mandatory=$true)][Alias('a')][string]$AppID = "",
    [Parameter(Mandatory=$true)][Alias('k')][string]$AppKey = ""
    )

$oauth = $null

# enumerate all XML files in the specified folders and create a array of objects with info we need
Function EnumPoliciesFromPath( [string]$PolicyPath ) {
    $files = get-childitem -path $policypath -name | Where-Object {! $_.PSIsContainer }
    $arr = @()
    foreach( $file in $files ) {
        #write-output "Reading Policy XML file $file..."
        $PolicyFile = (Join-Path -Path $PolicyPath -ChildPath $file)
        $PolicyData = Get-Content $PolicyFile
        [xml]$xml = $PolicyData
        $policy = New-Object System.Object
        $policy | Add-Member -type NoteProperty -name "PolicyId" -Value $xml.TrustFrameworkPolicy.PolicyId
        $policy | Add-Member -type NoteProperty -name "BasePolicyId" -Value $xml.TrustFrameworkPolicy.BasePolicy.PolicyId
        $policy | Add-Member -type NoteProperty -name "Uploaded" -Value $false
        $policy | Add-Member -type NoteProperty -name "FilePath" -Value $PolicyFile
        $policy | Add-Member -type NoteProperty -name "xml" -Value $xml
        $policy | Add-Member -type NoteProperty -name "PolicyData" -Value $PolicyData
        $arr += $policy
    }
    return $arr
}

# process each Policy object in the array. For each that has a BasePolicyId, follow that dependency link
# first call has to be with BasePolicyId null (base/root policy) for this to work
Function ProcessPolicies( $arrP, $BasePolicyId ) {
    foreach( $p in $arrP ) {
        if ( $p.xml.TrustFrameworkPolicy.TenantId -ne $TenantName ) {
            write-output "$($p.PolicyId) has wrong tenant configured $($p.xml.TrustFrameworkPolicy.TenantId) - skipped"
        } else {
            if ( $BasePolicyId -eq $p.BasePolicyId -and $p.Uploaded -eq $false ) {
                # upload this one
                UploadPolicy $p.PolicyId $p.PolicyData
                $p.Uploaded = $true
                # process all policies that has a ref to this one
                ProcessPolicies $arrP $p.PolicyId
            }
        }
    }
}

# invoke the Graph REST API to upload the Policy
Function UploadPolicy( [string]$PolicyId, [string]$PolicyData) {
    # https://docs.microsoft.com/en-us/graph/api/trustframework-put-trustframeworkpolicy?view=graph-rest-beta
    # upload the Custom Policy
    write-host "Uploading policy $PolicyId..."
    $url = "https://graph.microsoft.com/beta/trustFramework/policies/$PolicyId/`$value"
    $resp = Invoke-RestMethod -Method PUT -Uri $url -ContentType "application/xml" -Headers @{'Authorization'="$($oauth.token_type) $($oauth.access_token)"} -Body $PolicyData
    write-output $resp.TrustFrameworkPolicy
}

# either try and use the tenant name passed or grab the tenant from current session
<##>
$tenantID = ""
if ( "" -eq $TenantName ) {
    write-host "Getting Tenant info..."
    $tenant = Get-AzureADTenantDetail
    if ( $null -eq $tenant ) {
        write-host "Not logged in to a B2C tenant"
        exit 1
    }
    $tenantName = $tenant.VerifiedDomains[0].Name
    $tenantID = $tenant.ObjectId
} else {
    if ( !($TenantName -imatch ".onmicrosoft.com") ) {
        $TenantName = $TenantName + ".onmicrosoft.com"
    }
    $resp = Invoke-RestMethod -Uri "https://login.windows.net/$TenantName/v2.0/.well-known/openid-configuration"
    $tenantID = $resp.authorization_endpoint.Split("/")[3]    
}
<##>

<##>
if ( "" -eq $tenantID ) {
    write-host "Unknown Tenant"
    exit 2
}
write-host "Tenant:  `t$tenantName`nTenantID:`t$tenantId"

# check the B2C Graph App passed
$app = Get-AzureADApplication -Filter "AppID eq '$AppID'"
if ( $null -eq $app ) {
    write-host "App not found in B2C tenant: $AppID"
    exit 3
} else {
    write-host "`Authenticating as App $($app.DisplayName), AppID $AppID"
}
<##>

# load the XML Policy files
$arr = EnumPoliciesFromPath $PolicyPath

# https://docs.microsoft.com/en-us/azure/active-directory/users-groups-roles/directory-assign-admin-roles#b2c-user-flow-administrator
# get an access token for the B2C Graph App
$oauthBody  = @{grant_type="client_credentials";resource="https://graph.microsoft.com";client_id=$AppID;client_secret=$AppKey}
$oauth      = Invoke-RestMethod -Method Post -Uri "https://login.microsoft.com/$tenantName/oauth2/token?api-version=1.0" -Body $oauthBody

# upload policies - start with those who have no BasePolicyId dependency (null)
ProcessPolicies $arr $null     

# check what hasn't been uploaded
foreach( $p in $arr ) {
    if ( $p.Uploaded -eq $false ) {
        write-output "$($p.PolicyId) has a refence to $($p.BasePolicyId) which doesn't exists in the folder - not uploaded"
    }
}
