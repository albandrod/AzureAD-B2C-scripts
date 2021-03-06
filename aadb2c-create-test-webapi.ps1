param (
    [Parameter(Mandatory=$true)][Alias('n')][string]$DisplayName = "Test-WebApi",
    [Parameter(Mandatory=$false)][Alias('a')][string]$AppID = "",
    [Parameter(Mandatory=$false)][Alias('k')][string]$AppKey = ""
    )

$oauth = $null
if ( "" -eq $AppID ) { $AppID = $env:B2CAppId }
if ( "" -eq $AppKey ) { $AppKey = $env:B2CAppKey }

$tenant = Get-AzureADTenantDetail
$tenantName = $tenant.VerifiedDomains[0].Name

Function CreateScope( [string] $value, [string] $userConsentDisplayName, [string] $userConsentDescription, 
                      [string] $adminConsentDisplayName, [string] $adminConsentDescription)
{
    $scope = New-Object Microsoft.Open.AzureAD.Model.OAuth2Permission
    $scope.Id = New-Guid
    $scope.Value = $value
    $scope.UserConsentDisplayName = $userConsentDisplayName
    $scope.UserConsentDescription = $userConsentDescription
    $scope.AdminConsentDisplayName = $adminConsentDisplayName
    $scope.AdminConsentDescription = $adminConsentDescription
    $scope.IsEnabled = $true
    $scope.Type = "User"
    return $scope
}

$requiredResourceAccess=@"
[
    {
        "resourceAppId": "00000003-0000-0000-c000-000000000000",
        "resourceAccess": [
            {
                "id": "37f7f235-527c-4136-accd-4a02d197296e",
                "type": "Scope"
            },
            {
                "id": "7427e0e9-2fba-42fe-b0c0-848c9e6a8182",
                "type": "Scope"
            }
        ]
    }
]
"@ | ConvertFrom-json
        
$reqAccess=@()
foreach( $resApp in $requiredResourceAccess ) {
    $req = New-Object -TypeName "Microsoft.Open.AzureAD.Model.RequiredResourceAccess"
    $req.ResourceAppId = $resApp.resourceAppId
    foreach( $ra in $resApp.resourceAccess ) {
        $req.ResourceAccess += New-Object -TypeName "Microsoft.Open.AzureAD.Model.ResourceAccess" -ArgumentList $ra.Id,$ra.type
    }
    $reqAccess += $req
}

$scopes=@()
$scope = CreateScope -value "Demo.Read"  `
                -userConsentDisplayName "Allow demo read"  `
                -userConsentDescription "Allow the demo application to read demo data on your behalf."  `
                -adminConsentDisplayName "Allow demo read"  `
                -adminConsentDescription "Allow the demo application to read demo data on your behalf."
$scopes += $scope            

write-output "Creating application $DisplayName"
$app = New-AzureADApplication -DisplayName $DisplayName -IdentifierUris "https://$TenantName/$DisplayName" -ReplyUrls @("https://jwt.ms") -RequiredResourceAccess $reqAccess -OAuth2Permission $scopes -Oauth2AllowImplicitFlow $true

write-output "Creating ServicePrincipal $DisplayName"
$sp = New-AzureADServicePrincipal -AccountEnabled $true -AppId $App.AppId -AppRoleAssignmentRequired $false -DisplayName $DisplayName

Start-Sleep 15
$oauthBody  = @{grant_type="client_credentials";resource="https://graph.microsoft.com/";client_id=$AppID;client_secret=$AppKey;scope="https://graph.microsoft.com/.default Application.ReadWrite.All"}
$oauth      = Invoke-RestMethod -Method Post -Uri "https://login.microsoft.com/$tenantName/oauth2/token?api-version=1.0" -Body $oauthBody
$apiUrl = "https://graph.microsoft.com/v1.0/applications/$($app.objectId)"
$body = @{ SignInAudience = "AzureADandPersonalMicrosoftAccount" }
Invoke-RestMethod -Uri $apiUrl -Headers @{Authorization = "Bearer $($oauth.access_token)" }  -Method PATCH -Body ($body | ConvertTo-json) -ContentType "application/json"

& $PSScriptRoot\aadb2c-app-grant-permission.ps1 -n $DisplayName