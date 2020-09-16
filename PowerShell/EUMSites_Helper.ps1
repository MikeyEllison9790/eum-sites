﻿function GetManagedCredentials() {
    [OutputType([System.Management.Automation.PSCredential])]
    Param
    (
        [Parameter(Mandatory = $true)][string] $managedCredentials,
        [Parameter(Mandatory = $true)][string] $managedCredentialsType
    )

    if (-not(Get-InstalledModule -Name "CredentialManager" -RequiredVersion "2.0")) {
        Write-Verbose -Verbose -Message "Required Windows Credential Manager 2.0 PowerShell Module not found. Please install the module by entering the following command in PowerShell: ""Install-Module -Name ""CredentialManager"" -RequiredVersion 2.0"""
        return $null
    }

    #-----------------------------------------------------------------------
    # Get credentials from Windows Credential Manager
    #-----------------------------------------------------------------------
    $Credentials = Get-StoredCredential -Target $managedCredentials 
    switch ($managedCredentialsType) {
        "UsernamePassword" {
            if ($Credentials -eq $null) {
                $UserName = Read-Host "Enter the username to connect with for $managedCredentials"
                $Password = Read-Host "Enter the password for $UserName" -AsSecureString 
                $SaveCredentials = Read-Host "Save the credentials in Windows Credential Manager (Y/N)?"
                if (($SaveCredentials -eq "y") -or ($SaveCredentials -eq "Y")) {
                    $temp = New-StoredCredential -Target $managedCredentials -UserName $UserName -SecurePassword $Password -Persist Enterprise -Type Generic 
                }
                $Credentials = New-Object -typename System.Management.Automation.PSCredential -argumentlist $UserName, $Password
            }
            else {
                Write-Verbose -Verbose -Message "Connecting with username $($Credentials.UserName)" 
            }
        }

        "ClientIdSecret" {
            if ($Credentials -eq $null) {
                $ClientID = Read-Host "Enter the Client Id to connect with for $managedCredentials"
                $ClientSecret = Read-Host "Enter the Secret" -AsSecureString
                $SaveCredentials = Read-Host "Save the credentials in Windows Credential Manager (Y/N)?"
                if (($SaveCredentials -eq "y") -or ($SaveCredentials -eq "Y")) {
                    $temp = New-StoredCredential -Target $managedCredentials -UserName $ClientID -SecurePassword $ClientSecret -Persist Enterprise -Type Generic
                }
                $Credentials = New-Object -typename System.Management.Automation.PSCredential -argumentlist $ClientID, $ClientSecret
            }
            else {
                Write-Verbose -Verbose -Message "Connecting with Client Id $($Credentials.UserName)" 
            }
        }

        "EUMClientIdSecret" {
            if ($Credentials -eq $null) {
                [string]$Global:EUMClientID = Read-Host "Enter the Client Id to connect with for $managedCredentials"
                [string]$Global:EUMSecret = Read-Host "Enter the Secret" -AsSecureString
                $SaveCredentials = Read-Host "Save the credentials in Windows Credential Manager (Y/N)?"
                if (($SaveCredentials -eq "y") -or ($SaveCredentials -eq "Y")) {
                    $temp = New-StoredCredential -Target $managedCredentials -UserName $EUMClientID -SecurePassword $EUMSecret -Persist Enterprise -Type Generic
                }
            }
            else {
                [string]$Global:EUMClientID = $Credentials.UserName
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credentials.Password)
                [string]$Global:EUMSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                Write-Verbose -Verbose -Message "Connecting with Client Id $($EUMClientID)" 
            }
        }
    }

    return ($Credentials)
}
    
function LoadEnvironmentSettings() {

    [string]$Global:pnpTemplatePath = "c:\pnptemplates"

    # Check if running in Azure Automation or locally
    $Global:AzureAutomation = (Get-Command "Get-AutomationVariable" -errorAction SilentlyContinue)
    if ($AzureAutomation) {
        # Get automation variables
        $Global:SPCredentials = Get-AutomationPSCredential -Name 'SPOnlineCredentials'

        [string]$Global:SiteListName = Get-AutomationVariable -Name 'SiteListName'
        [string]$Global:TeamsChannelsListName = Get-AutomationVariable -Name 'TeamsChannelsListName'
        [string]$Global:WebAppURL = Get-AutomationVariable -Name 'WebAppURL'
        [string]$Global:AdminURL = $WebAppURL.Replace(".sharepoint.com", "-admin.sharepoint.com")
        [string]$Global:SitesListSiteRelativeURL = Get-AutomationVariable -Name 'SitesListSiteURL'
        [string]$Global:SitesListSiteURL = "$($WebAppURL)$($SitesListSiteRelativeURL)"
        [string]$Global:SiteCollectionAdministrator = Get-AutomationVariable -Name 'siteCollectionAdministrator'
        [string]$Global:TeamsSPFxAppId = Get-AutomationVariable -Name 'TeamsSPFxAppId'

        [boolean]$Global:IsSharePointOnline = $WebAppURL.ToLower() -like "*.sharepoint.com"

        $Global:AADCredentials = (Get-AutomationPSCredential -Name 'AADCredentials' -ErrorAction SilentlyContinue)
        if ($AADCredentials -ne $null) {
            $Global:AADClientID = $AADCredentials.UserName
            $Global:AADSecret = (New-Object PSCredential "user", $AADCredentials.Password).GetNetworkCredential().Password
            $Global:AADDomain = Get-AutomationVariable -Name 'AADDomain'
        }
    }
    else {
        [xml]$config = Get-Content -Path "$($PSScriptRoot)\sharepoint.config"

        [System.Array]$Global:managedPaths = $config.settings.common.managedPaths.path
        [string]$Global:SiteListName = $config.settings.common.siteLists.siteListName
        [string]$Global:TeamsChannelsListName = $config.settings.common.siteLists.teamsChannelsListName

        $environmentId = $config.settings.common.defaultEnvironment

        if (-not $environmentId) {
            # Get the value from the last run as a default
            if ($environment.id) {
                $defaultText = "(Default - $($environment.id))"
            }

            #-----------------------------------------------------------------------
            # Prompt for the environment defined in the config
            #-----------------------------------------------------------------------

            Write-Verbose -Verbose -Message "`n***** AVAILABLE ENVIRONMENTS *****"
            $config.settings.environments.environment | ForEach {
                Write-Verbose -Verbose -Message "$($_.id)`t $($_.name) - $($_.webApp.URL)"
            }
            Write-Verbose -Verbose -Message "***** AVAILABLE ENVIRONMENTS *****"

            Do {
                [int]$environmentId = Read-Host "Enter the ID of the environment from the above list $defaultText"
            }
            Until (($environmentId -gt 0) -or ($environment.id -gt 0))
        }

        if ($environmentId -eq 0) {
            $environmentId = $environment.id
        }

        [System.Xml.XmlLinkedNode]$Global:environment = $config.settings.environments.environment | Where { $_.id -eq $environmentId }

        # Set variables based on environment selected
        [string]$Global:WebAppURL = $environment.webApp.url
        [string]$Global:AdminURL = $environment.webApp.url.Replace(".sharepoint.com", "-admin.sharepoint.com")
        [string]$Global:SitesListSiteRelativeURL = $environment.webApp.sitesListSiteCollectionPath
        [string]$Global:SitesListSiteURL = "$($WebAppURL)$($SitesListSiteRelativeURL)"
        [string]$Global:SiteCollectionAdministrator = $environment.webApp.siteCollectionAdministrator
        [string]$Global:TeamsSPFxAppId = $environment.webApp.teamsSPFxAppId
        $Global:Domain_FK = $environment.eumAPI.domainFK
        $Global:SystemConfiguration_FK = $environment.eumAPI.systemConfigurationFK
        
        Write-Verbose -Verbose -Message "Environment set to $($environment.name) - $($environment.webApp.URL) `n"

        [boolean]$Global:IsSharePointOnline = $WebAppURL.ToLower() -like "*.sharepoint.com"

        $Global:SPCredentials = GetManagedCredentials -managedCredentials $environment.webApp.managedCredentials -ManagedCredentialsType $environment.webApp.managedCredentialsType

        if ($environment.graphAPI.managedCredentials -ne $null) {
            $AADCredentials = GetManagedCredentials -managedCredentials $environment.graphAPI.managedCredentials -ManagedCredentialsType $environment.graphAPI.managedCredentialsType
            if ($AADCredentials -ne $null) {
                $Global:AADClientID = $AADCredentials.UserName
                $Global:AADSecret = (New-Object PSCredential "user", $AADCredentials.Password).GetNetworkCredential().Password
                $Global:AADDomain = $environment.graphAPI.AADDomain
            }
        }

        if ($environment.eumAPI.managedCredentials -ne $null) {
            GetManagedCredentials -managedCredentials $environment.eumAPI.managedCredentials -ManagedCredentialsType $environment.eumAPI.managedCredentialsType
            [string]$Global:EUMURL = $environment.eumAPI.url
        }
    }
}


function Helper-Connect-PnPOnline() {
    Param
    (
        [Parameter(Mandatory = $true)][string] $URL
    )

    if ($O365ClientID -and $O365ClientSecret) {
        $Conn = Connect-PnPOnline -Url $URL -AppId $O365ClientID -AppSecret $O365ClientSecret -ReturnConnection
    }
    else {
        $Conn = Connect-PnPOnline -Url $URL -Credentials $SPCredentials -ReturnConnection
    }

    return $Conn
}

function GetBreadcrumbHTML() {
    Param
    (
        [Parameter(Mandatory = $true)][string] $siteURL,
        [Parameter(Mandatory = $true)][string] $siteTitle,
        [Parameter(Mandatory = $false)][string] $parentURL
    )
    [string]$parentBreadcrumbHTML = ""

    if ($parentURL) {
        $connLandingSite = Helper-Connect-PnPOnline -Url $SitesListSiteURL

        $parentListItem = Get-PnPListItem -List $SiteListName -Connection $connLandingSite -Query "
				<View>
						<Query>
								<Where>
										<Eq>
												<FieldRef Name='EUMSiteURL'/>
												<Value Type='Text'>$($parentURL)</Value>
										</Eq>
								</Where>
						</Query>
				</View>"

        if ($parentListItem) {
            [string]$parentBreadcrumbHTML = $parentListItem["EUMBreadcrumbHTML"]
        }
        else {
            Write-Verbose -Verbose -Message "No entry found for $parentURL"
        }
    }

    $siteURL = $siteURL.Replace($webAppURL, "")
    [string]$breadcrumbHTML = "<a href=`"$($siteURL)`">$($siteTitle)</a>"
    if ($parentBreadcrumbHTML) {
        $breadcrumbHTML = $parentBreadcrumbHTML + ' &gt; ' + $breadcrumbHTML
    }
    return $breadcrumbHTML
}

function GetGraphAPIBearerToken() {
    $scope = "https://graph.microsoft.com/.default"
    $authorizationUrl = "https://login.microsoftonline.com/$($AADDomain)/oauth2/v2.0/token"

    Add-Type -AssemblyName System.Web

    $requestBody = @{
        client_id     = $AADClientID
        client_secret = $AADSecret
        scope         = $scope
        grant_type    = 'client_credentials'
    }

    $request = @{
        ContentType = 'application/x-www-form-urlencoded'
        Method      = 'POST'
        Body        = $requestBody
        Uri         = $authorizationUrl
    }

    $response = Invoke-RestMethod @request

    return $response.access_token
}

function GetGraphAPIServiceAccountBearerToken() {
    $scope = "https://graph.microsoft.com/.default"
    $authorizationUrl = "https://login.microsoftonline.com/$($AADDomain)/oauth2/v2.0/token"

    Add-Type -AssemblyName System.Web

    $requestBody = @{
        client_id     = $AADClientID
        client_secret = $AADSecret
        scope         = $scope
        grant_type    = 'password'
        username      = "$($SPCredentials.UserName)"
        password      = "$($SPCredentials.GetNetworkCredential().Password)"
    }

    $request = @{
        ContentType = 'application/x-www-form-urlencoded'
        Method      = 'POST'
        Body        = $requestBody
        Uri         = $authorizationUrl
    }

    $response = Invoke-RestMethod @request

    return $response.access_token
}

function AddOneNoteTeamsChannelTab() {
    Param
    (
        [parameter(Mandatory = $true)]$groupId,
        [parameter(Mandatory = $true)]$channelName,
        [parameter(Mandatory = $true)]$teamsChannelId,
        [parameter(Mandatory = $true)]$siteURL
    )

    $graphApiBaseUrl = "https://graph.microsoft.com/v1.0"

    # Retrieve access token for graph API
    $accessToken = GetGraphAPIBearerToken

    # Call the Graph API to get the notebook
    Write-Verbose -Verbose -Message "Retrieving notebook for group $($groupId)..."
    $graphGETEndpoint = "$($graphApiBaseUrl)/groups/$($groupId)/onenote/notebooks"

    # The notebook is not immediately available when the team site is created so use retry logic
    $getResponse = $null 
    while (($retries -lt 120) -and ($getResponse -eq $null -or $getResponse.value -eq $null)) {
        Start-Sleep -Seconds 30
        $retries += 1
        $getResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphGETEndpoint -Method Get -ContentType 'application/json'
    }

    if ($getResponse -ne $null -and $getResponse.value -ne $null) {
        $notebookId = $getResponse.value.id
        $oneNoteWebUrl = $getResponse.value.links.oneNoteWebUrl

        # Call the Graph API to create a OneNote section
        Write-Verbose -Verbose -Message "Adding section $($channelName) to notebook for group $($groupId)..."
        $graphPOSTEndpoint = "$($graphApiBaseUrl)/groups/$($groupId)/onenote/notebooks/$($notebookId)/sections"
        $graphPOSTBody = @{
            "displayName" = $channelName
        }
        $postResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphPOSTEndpoint -Body $($graphPOSTBody | ConvertTo-Json) -Method Post -ContentType 'application/json'
        $sectionId = $postResponse.id

        # Add a blank page to the section created above (required in order to link to the section)
        Write-Verbose -Verbose -Message "Adding page to section $($channelName) in notebook..."
        $graphPOSTEndpoint = "$($graphApiBaseUrl)/groups/$($groupId)/onenote/sections/$($sectionId)/pages"
        $graphPOSTBody = "<!DOCTYPE html><html><head><title></title><meta name='created' content='" + $(Get-Date -Format s) + "' /></head><body></body></html>"
        $postResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphPOSTEndpoint -Body $graphPOSTBody -Method Post -ContentType 'text/html'

        # Add a tab to the team channel to the OneNote section    
        Write-Verbose -Verbose -Message "Adding OneNote tab to channel $($channelName)..."
        $configurationProperties = @{
            "contentUrl" = "https://www.onenote.com/teams/TabContent?notebookSource=PickSection&notebookSelfUrl=https://www.onenote.com/api/v1.0/myOrganization/groups/$($groupId)/notes/notebooks/$($notebookId)&oneNoteWebUrl=$($oneNoteWebUrl)&notebookName=OneNote&siteUrl=$($siteURL)&createdTeamType=Standard&wd=target(//$($channelName).one|/)&sectionId=$($notebookId)9&notebookIsDefault=true&ui={locale}&tenantId={tid}"
            "removeUrl"  = "https://www.onenote.com/teams/TabRemove?notebookSource=PickSection&notebookSelfUrl=https://www.onenote.com/api/v1.0/myOrganization/groups/$($groupId)/notes/notebooks/$($notebookId)c&oneNoteWebUrl=$($oneNoteWebUrl)&notebookName=OneNote&siteUrl=$($siteURL)&createdTeamType=Standard&wd=target(//$($channelName).one|/)&sectionId=$($notebookId)9&notebookIsDefault=true&ui={locale}&tenantId={tid}"
            "websiteUrl" = "https://www.onenote.com/teams/TabRedirect?redirectUrl=$($oneNoteWebUrl)?wd=target(%2F%2F$($channelName).one%7C%2F)"
        }
        $graphPOSTBody = @{
            "teamsApp@odata.bind" = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/0d820ecd-def2-4297-adad-78056cde7c78"
            "displayName"         = "OneNote"
            "configuration"       = $configurationProperties
        }
        $graphPOSTEndpoint = "$($graphApiBaseUrl)/teams/$($groupId)/channels/$($teamsChannelId)/tabs"
        $postResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphPOSTEndpoint -Body $($graphPOSTBody | ConvertTo-Json) -Method Post -ContentType 'application/json'
    }
    else {
        Write-Error "Could not retrieve notebook for group $($groupId)"
    }
}

function AddTeamsChannelRequestFormToChannel() {
    Param
    (
        [parameter(Mandatory = $true)]$groupId,
        [parameter(Mandatory = $true)]$teamsChannelId
    )
    
    $graphApiBaseUrl = "https://graph.microsoft.com/v1.0"

    # Retrieve access token for graph API
    $accessToken = GetGraphAPIBearerToken

    # First add the app to the team
    Write-Verbose -Verbose -Message "Adding Add channel SPFx Web Part app to team for groupId $($groupId)..."
    $graphPOSTEndpoint = "$($graphApiBaseUrl)/teams/$($groupId)/installedApps"
    $graphPOSTBody = @{
        "teamsApp@odata.bind" = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/$($TeamsSPFxAppId)"
        "id"                  = "$($TeamsSPFxAppId)"
        "externalId"          = "75dbe34f-74a5-4bbb-9495-41701c0d7ac0"
        "name"                = "Add channel"
        "version"             = "0.1"
        "distributionMethod"  = "organization"
    }
    $postResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphPOSTEndpoint -Body $($graphPOSTBody | ConvertTo-Json) -Method Post -ContentType 'application/json'

    Start-Sleep -Seconds 60

    # Add the SPFx web part to the channel
    Write-Verbose -Verbose -Message "Adding Add channel SPFx Web Part tab to channel $($teamsChannelId)..."
    $graphPOSTEndpoint = "$($graphApiBaseUrl)/teams/$($groupId)/channels/$($teamsChannelId)/tabs"
    $graphPOSTBody = @{
        "displayName"         = "Add channel"
        "teamsApp@odata.bind" = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/$($TeamsSPFxAppId)"
    }
    $postResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphPOSTEndpoint -Body $($graphPOSTBody | ConvertTo-Json) -Method Post -ContentType 'application/json'
}

function AddGroupOwner() {
    Param
    (
        [parameter(Mandatory = $true)]$groupId,
        [parameter(Mandatory = $true)]$email
    )
    
    $graphApiBaseUrl = "https://graph.microsoft.com/v1.0"

    # Retrieve access token for graph API
    $accessToken = GetGraphAPIBearerToken

    Write-Verbose -Verbose -Message "Adding $($email) as owner to groupId $($groupId)..."    
    $graphPOSTEndpoint = "$($graphApiBaseUrl)/groups/$($groupId)/owners/`$ref"
    $graphPOSTBody = @{
        "@odata.id" = "$($graphApiBaseUrl)/users/$($email)"
    }


    $retries = 0
    $groupOwnerAdded = $false
    while (($retries -lt 20) -and (-not $groupOwnerAdded)) {
        try {
            $retries += 1
                        
            $postResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphPOSTEndpoint -Body $($graphPOSTBody | ConvertTo-Json) -Method Post -ContentType 'application/json'
            $groupOwnerAdded = $true
        }
        catch {      
            Write-Verbose -Verbose -Message "Failed adding $($email) as owner to groupId $($groupId)..."    
            Write-Verbose -Verbose -Message $_
            Start-Sleep -Seconds 30
        }
    }
}

function AddTeamPlanner() {
    Param
    (
        [parameter(Mandatory = $true)]$groupId,
        [parameter(Mandatory = $true)]$planTitle
    )
    
    $graphApiBaseUrl = "https://graph.microsoft.com/v1.0"

    # Retrieve access token for graph API
    $accessToken = GetGraphAPIServiceAccountBearerToken

    Write-Verbose -Verbose -Message "Creating plan $($planTitle) for groupId $($groupId)..."
    $graphPOSTEndpoint = "$($graphApiBaseUrl)/planner/plans"
    $graphPOSTBody = @{
        "owner" = $($groupId)
        "title" = $($planTitle)
    }
    $postResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphPOSTEndpoint -Body $($graphPOSTBody | ConvertTo-Json) -Method Post -ContentType 'application/json'

    return $postResponse.id
}

function AddPlannerTeamsChannelTab() {
    Param
    (
        [parameter(Mandatory = $true)]$groupId,
        [parameter(Mandatory = $true)]$planTitle,
        [parameter(Mandatory = $true)]$planId,
        [parameter(Mandatory = $true)]$channelName,
        [parameter(Mandatory = $true)]$teamsChannelId
    )

    $graphApiBaseUrl = "https://graph.microsoft.com/v1.0"

    # Retrieve access token for graph API
    $accessToken = GetGraphAPIBearerToken
    Write-Verbose -Verbose -Message $accessToken

    Write-Verbose -Verbose -Message "Adding Planner tab for plan $($planTitle) to channel $($channelName)..."
    $configurationProperties = @{
        "entityId"   = $planId
        "contentUrl" = "https://tasks.office.com/$($AADDomain)/Home/PlannerFrame?page=7&planId=$($planId)"
        "removeUrl"  = "https://tasks.office.com/$($AADDomain)/Home/PlannerFrame?page=7&planId=$($planId)"
        "websiteUrl" = "https://tasks.office.com/$($AADDomain)/Home/PlannerFrame?page=7&planId=$($planId)"
    }

    $graphPOSTBody = @{
        "teamsApp@odata.bind" = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/com.microsoft.teamspace.tab.planner"
        "displayName"         = "Planner"
        "configuration"       = $configurationProperties
    }

    $graphPOSTEndpoint = "$($graphApiBaseUrl)/teams/$($groupId)/channels/$($teamsChannelId)/tabs"
    $postResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphPOSTEndpoint -Body $($graphPOSTBody | ConvertTo-Json) -Method Post -ContentType 'application/json'
}

function GetGroupIdByName() {
    Param
    (
        [parameter(Mandatory = $true)]$groupName
    )

    $graphApiBaseUrl = "https://graph.microsoft.com/v1.0"

    # Retrieve access token for graph API
    $accessToken = GetGraphAPIBearerToken
    $groupFormatted = $groupName.replace("'", "''")
    Write-Verbose -Verbose -Message "Retrieving group ID for group $($groupFormatted)..."
    $graphGETEndpoint = "$($graphApiBaseUrl)/groups?`$filter=displayName eq '$($groupFormatted)'"

    try {
        $getResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphGETEndpoint -Method Get -ContentType 'application/json'
        Write-Verbose -Verbose -Message "Retrieving group ID $($getResponse.value.id) for group $($groupName)."
        return $getResponse.value.id
    }
    catch [System.Net.WebException] {
        if ([int]$_.Exception.Response.StatusCode -eq 404) {
            return $null
        }
        else {
            Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
            Write-Error "Exception Message: $($_.Exception.Message)"
        }
    }
    catch {
        Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Error "Exception Message: $($_.Exception.Message)"
    }
}

function GetGroupIdByAlias() {
    Param
    (
        [parameter(Mandatory = $true)]$groupAlias
    )

    $graphApiBaseUrl = "https://graph.microsoft.com/v1.0"

    # Retrieve access token for graph API
    $accessToken = GetGraphAPIBearerToken
    Write-Verbose -Verbose -Message "Retrieving group ID for group $($groupAlias)..."
    $graphGETEndpoint = "$($graphApiBaseUrl)/groups?`$filter=mailNickname eq '$($groupAlias)'"

    try {
        $getResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphGETEndpoint -Method Get -ContentType 'application/json'
        Write-Verbose -Verbose -Message "Retrieving group ID $($getResponse.value.id) for group $($groupAlias)."
        return $getResponse.value.id
    }
    catch [System.Net.WebException] {
        if ([int]$_.Exception.Response.StatusCode -eq 404) {
            return $null
        }
        else {
            Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
            Write-Error "Exception Message: $($_.Exception.Message)"
        }
    }
    catch {
        Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Error "Exception Message: $($_.Exception.Message)"
    }
}

function ConvertGroupNameToAlias() {
    Param
    (
        [parameter(Mandatory = $true)]$groupName
    )
	[string]$groupAlias = $groupName.Replace(' ', '-')
    # https://docs.microsoft.com/en-us/office/troubleshoot/error-messages/username-contains-special-character
    # Convert any accented characters
    $groupAlias = [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($groupAlias))
    # Remove any special characters
    $groupAlias = $groupAlias -replace '[^a-zA-Z0-9\-]', ''

    return $groupAlias
}

function GetGroupSiteUrl() {
    Param
    (
        [parameter(Mandatory = $true)]$groupId
    )

    $graphApiBaseUrl = "https://graph.microsoft.com/v1.0"

    # Retrieve access token for graph API
    $accessToken = GetGraphAPIBearerToken

    Write-Verbose -Verbose -Message "Retrieving site URL for group $($groupId)..."
    $graphGETEndpoint = "$($graphApiBaseUrl)/groups/$($groupId)/sites/root/webUrl"

    try {
        $getResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphGETEndpoint -Method Get -ContentType 'application/json'
        return $getResponse.value
    }
    catch [System.Net.WebException] {
        if ([int]$_.Exception.Response.StatusCode -eq 404) {
            return $null
        }
        else {
            Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
            Write-Error "Exception Message: $($_.Exception.Message)"
        }
    }
    catch {
        Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
        Write-Error "Exception Message: $($_.Exception.Message)"
    }
}

function GetUsernameFromEmail() {
    [OutputType([string])]
    Param
    (
        [parameter(Mandatory = $true)]$email
    )
    try {
        $graphApiBaseUrl = "https://graph.microsoft.com/v1.0"
        # Retrieve access token for graph API
        $accessToken = GetGraphAPIBearerToken

        Write-Verbose -Verbose -Message "Getting username for $email ..."    
        $graphGETEndpoint = "$($graphApiBaseUrl)/users?`$filter=mail eq '$email'&`$select=userPrincipalName"

        $getResponse = Invoke-RestMethod -Headers @{Authorization = "Bearer $accessToken" } -Uri $graphGETEndpoint -Method Get -ContentType 'application/json'
        Write-Verbose -Verbose -Message "Retrieving username $($getResponse.value[0].userPrincipalName) for group $($email)."
        return $getResponse.value[0].userPrincipalName
    }
    catch {
        Write-Verbose -Verbose -Message "User NOT found for $email"
        return $null
    }
}

function ProvisionSite {
    Param
    (
        [Parameter (Mandatory = $True)][int]$listItemID
    )

    Write-Verbose -Verbose -Message "listItemID = $($listItemID)"

    $connLandingSite = Helper-Connect-PnPOnline -Url $SitesListSiteURL

    New-Item -Path $pnpTemplatePath -ItemType "directory" -Force | out-null

    $pnpTemplates = Find-PnPFile -List "PnPTemplates" -Match *.xml -Connection $connLandingSite
    $pnpTemplates | ForEach-Object {
        $File = Get-PnPFile -Url "$($SitesListSiteRelativeURL)/pnptemplates/$($_.Name)" -Path $pnpTemplatePath -AsFile -Force -Connection $connLandingSite
    }

    # Get the specific Site Collection List item in master site for the site that needs to be created
    $pendingSite = Get-PnPListItem -Connection $connLandingSite -List $SiteListName -Query "
    <View>
        <Query>
            <Where>
                <And>
                    <And>
                        <Eq>
                            <FieldRef Name='ID'/>
                            <Value Type='Integer'>$listItemID</Value>
                        </Eq>
                        <IsNull>
                            <FieldRef Name='EUMSiteCreated'/>
                        </IsNull>
                    </And>
                    <Eq>
                        <FieldRef Name='_ModerationStatus' />
                        <Value Type='ModStat'>0</Value>
                    </Eq>
                </And>
            </Where>
        </Query>
        <ViewFields>
            <FieldRef Name='ID'></FieldRef>
            <FieldRef Name='Title'></FieldRef>
            <FieldRef Name='EUMSiteURL'></FieldRef>
            <FieldRef Name='EUMAlias'></FieldRef>
            <FieldRef Name='EUMSiteVisibility'></FieldRef>
            <FieldRef Name='EUMBreadcrumbHTML'></FieldRef>
            <FieldRef Name='EUMParentURL'></FieldRef>
            <FieldRef Name='EUMSiteTemplate'></FieldRef>
            <FieldRef Name='EUMDivision'></FieldRef>
            <FieldRef Name='EUMCreateTeam'></FieldRef>
            <FieldRef Name='EUMCreateOneNote'></FieldRef>
            <FieldRef Name='EUMCreatePlanner'></FieldRef>
            <FieldRef Name='EUMExternalSharing'></FieldRef>
            <FieldRef Name='EUMDefaultSharingLinkType'></FieldRef>
            <FieldRef Name='EUMDefaultLinkPermission'></FieldRef>
            <FieldRef Name='Author'></FieldRef>
        </ViewFields>
    </View>"

    if ($pendingSite.Count -gt 0) {
        # Get the time zone of the master site
        $spWeb = Get-PnPWeb -Includes RegionalSettings.TimeZone -Connection $connLandingSite
        [int]$timeZoneId = $spWeb.RegionalSettings.TimeZone.Id

        [string]$siteTitle = $pendingSite["Title"]
        [string]$alias = $pendingSite["EUMAlias"]
        if ($alias) {
            # Replace spaces in Alias with dashes
            $alias = $alias -replace '\s', '-'
            $siteURL = "$($WebAppURL)/sites/$alias"
        }
        else {
            [string]$siteURL = "$($WebAppURL)$($pendingSite['EUMSiteURL'])"
        }

        [string]$siteVisibility = $pendingSite["EUMSiteVisibility"]
        [boolean]$publicGroup = $false
        if ($siteVisibility -eq "Public") { 
            $publicGroup = $true
        }

        [boolean]$eumCreateTeam = $false
        if ($pendingSite["EUMCreateTeam"] -ne $null) { 
            $eumCreateTeam = $pendingSite["EUMCreateTeam"] 
        }

        [boolean]$eumCreateOneNote = $false 
        if ($pendingSite["EUMCreateOneNote"] -ne $null) {
            $eumCreateOneNote = $pendingSite["EUMCreateOneNote"]
        }

        [boolean]$eumCreatePlanner = $false 
        if ($pendingSite["EUMCreatePlanner"] -ne $null) {
            $eumCreatePlanner = $pendingSite["EUMCreatePlanner"]
        }

        [string]$breadcrumbHTML = $pendingSite["EUMBreadcrumbHTML"]
        [string]$parentURL = $pendingSite["EUMParentURL"]
        [string]$eumExternalSharing = $pendingSite["EUMExternalSharing"]
        [string]$eumDefaultSharingLinkType = $pendingSite["EUMDefaultSharingLinkType"]
        [string]$eumDefaultLinkPermission = $pendingSite["EUMDefaultLinkPermission"]
        [string]$Division = $pendingSite["EUMDivision"].LookupValue
        [string]$eumSiteTemplate = $pendingSite["EUMSiteTemplate"].LookupValue
        [string]$author = $pendingSite["Author"].Email
        if ($IsSharePointOnline) {
            $author = GetUsernameFromEmail -email $pendingSite["Author"].Email
        }

        [boolean]$parentHubSite = $false
        
        $divisionSiteURL = Get-PnPListItem -Connection $connLandingSite -List "Divisions" -Query "
														<View>
															<Query>
																<Where>
																	<Eq>
																		<FieldRef Name='Title'/>
																		<Value Type='Text'>$Division</Value>
																	</Eq>
																</Where>
															</Query>
															<ViewFields>
																<FieldRef Name='Title'></FieldRef>
																<FieldRef Name='SiteURL'></FieldRef>
																<FieldRef Name='HubSite'></FieldRef>
															</ViewFields>
														</View>"
		
        if ($divisionSiteURL.Count -eq 1) {
            if ($parentURL -eq "") { 
                $parentURL = $divisionSiteURL["SiteURL"].Url 
            }

            if (($divisionSiteURL["HubSite"] -ne "") -and ($divisionSiteURL["HubSite"] -ne $null)) {
                $parentHubSite = $divisionSiteURL["HubSite"]
            }
        }

        $siteTemplate = Get-PnPListItem -Connection $connLandingSite -List "Site Templates" -Query "
												<View>
													<Query>
														<Where>
															<Eq>
																<FieldRef Name='Title'/>
																<Value Type='Text'>$eumSiteTemplate</Value>
															</Eq>
														</Where>
													</Query>
													<ViewFields>
														<FieldRef Name='Title'></FieldRef>
														<FieldRef Name='BaseClassicSiteTemplate'></FieldRef>
														<FieldRef Name='BaseModernSiteType'></FieldRef>
														<FieldRef Name='PnPSiteTemplate'></FieldRef>
														<FieldRef Name='JoinHubSite'></FieldRef>
													</ViewFields>
												</View>"
		
        $baseSiteTemplate = ""
        $baseSiteType = ""
        $pnpSiteTemplate = ""
        $joinHubSite = $false
        $siteCreated = $false

        if ($siteTemplate.Count -eq 1) {
            $baseSiteTemplate = $siteTemplate["BaseClassicSiteTemplate"]
            $baseSiteType = $siteTemplate["BaseModernSiteType"]

            if ($siteTemplate["JoinHubSite"] -ne $null) { 
                $joinHubSite = $siteTemplate["JoinHubSite"] 
            }

            if ($siteTemplate["PnPSiteTemplate"] -ne $null) {
                $pnpSiteTemplate = "$pnpTemplatePath\$($siteTemplate["PnPSiteTemplate"].LookupValue)"
            }
        }

        # Classic style sites
        if ($baseSiteTemplate) {
            # Create the site
            if ($siteCollection) {
                # Create site (if it exists, it will error but not modify the existing site)
                Write-Verbose -Verbose -Message "Creating site collection $($siteURL) with base template $($baseSiteTemplate). Please wait..."
                try {
                    New-PnPTenantSite -Title $siteTitle -Url $siteURL -Owner $author -TimeZone $timeZoneId -Template $baseSiteTemplate -RemoveDeletedSite -Wait -Force -Connection $connLandingSite -ErrorAction Stop
                }
                catch { 
                    Write-Error "Failed creating site collection $($siteURL)"
                    Write-Error $_
                }
            }
            else {
                # Connect to parent site
                $connParentSite = Helper-Connect-PnPOnline -Url $parentURL

                # Create the subsite
                Write-Verbose -Verbose -Message "Creating subsite $($siteURL) with base template $($baseSiteTemplate) under $($parentURL). Please wait..."

                [string]$subsiteURL = $siteURL.Replace($parentURL, "").Trim('/')
                New-PnPWeb -Title $siteTitle -Url $subsiteURL -Template $baseSiteTemplate -Connection $connParentSite

                Disconnect-PnPOnline
            }
            $siteCreated = $true

        }
        # Modern style sites
        else {
            # Create the site
            switch ($baseSiteType) {
                "CommunicationSite" {
                    try {
                        Write-Verbose -Verbose -Message "Creating site collection $($siteURL) with modern type $($baseSiteType). Please wait..."

                        if ($IsSharePointOnline) {
                            $siteURL = New-PnPSite -Type CommunicationSite -Title $siteTitle -Url $siteURL -ErrorAction Stop -Connection $connLandingSite
                        }
                        else {
                            New-PnPTenantSite -Title $siteTitle -Url $siteURL -Owner $author -TimeZone $timeZoneId -Template "SITEPAGEPUBLISHING#0" -Wait -Force -Connection $connLandingSite -ErrorAction Stop
                        }
                        $siteCreated = $true
                    }
                    catch { 
                        Write-Error "Failed creating site collection $($siteURL)"
                        Write-Error $_
                        return $false
                    }
                }
                "TeamSite" {
                    try {
                        Write-Verbose -Verbose -Message "Creating site collection $($siteURL) with modern type $($baseSiteType). Please wait..."
                        if ($IsSharePointOnline) {
                            if ($publicGroup) {
                                $siteURL = New-PnPSite -Type TeamSite -Title $siteTitle -Alias $alias -IsPublic -Connection $connLandingSite -ErrorAction Stop
                            }
                            else {
                                $siteURL = New-PnPSite -Type TeamSite -Title $siteTitle -Alias $alias -Connection $connLandingSite -ErrorAction Stop
                            }
                        }
                        else {
                            New-PnPTenantSite -Title $siteTitle -Url $siteURL -Owner $author -TimeZone $timeZoneId -Template "STS#3" -Wait -Force -Connection $connLandingSite -ErrorAction Stop
                        }
                        $siteCreated = $true

                        
                    }
                    catch { 
                        Write-Error "Failed creating site collection $($siteURL)"
                        Write-Error $_
                        return $false
                    }
                }
            }
        }

        if ($siteCreated) {
            if ($IsSharePointOnline) {
                $connAdmin = Helper-Connect-PnPOnline -Url $AdminURL
                $retries = 0

                $spSite = $null
                while (($spSite.Status -ne "Active") -and ($retries -lt 10) -and (($spSite.GroupId -ne "00000000-0000-0000-0000-000000000000") -or (-not $eumCreateTeam))) {
                    try {
                        $retries += 1
                        $spSite = Get-PnPTenantSite -Url $siteURL -Connection $connAdmin
                        Write-Verbose -Verbose -Message "Try: $retries, GroupId: $($spSite.GroupId)"
                    }
                    catch {      
                        Write-Verbose -Verbose -Message "Failed getting site $($siteURL)"
                        Write-Verbose -Verbose -Message $_
                        Start-Sleep -Seconds 30
                    }
                }
                Disconnect-PnPOnline

                $groupId = $spSite.GroupId
                Write-Verbose -Verbose -Message "GroupId = $($groupId)"
            }               

            $connSite = Helper-Connect-PnPOnline -Url $siteURL

            #Set the external sharing capabilities 
            if ($eumExternalSharing){
                switch ($eumExternalSharing){
                    'Anyone' {$externalSharingOption = "ExternalUserAndGuestSharing"  ; Break}
                    'New and existing guests' {$externalSharingOption = "ExternalUserSharingOnly" ; Break}
                    'Existing guests only' {$externalSharingOption = "ExistingExternalUserSharingOnly" ; Break}
                    'Only people in your organization' {$externalSharingOption = "Disabled" ; Break}
                }

                Write-Verbose -Verbose -Message "Setting external sharing to $($externalSharingOption)"
                Set-PnPSite -Identity $siteURL -Sharing $externalSharingOption
            }

            #Set the default sharing link type 
            if ($eumDefaultSharingLinkType){
                 switch ($eumDefaultSharingLinkType){
                    'Anyone with the link' {$defaultSharingLinkTypeOption = "AnonymousAccess" ; Break}
                    'Specific people' {$defaultSharingLinkTypeOption = "Direct" ; Break}
                    'Only people in your organization' {$defaultSharingLinkTypeOption = "Internal "; Break}
                    'People with existing access' {$defaultSharingLinkTypeOption = "ExistingAccess"; Break}  
                }
                if ($defaultSharingLinkTypeOption -and $defaultSharingLinkTypeOption -ne "ExistingAccess"){
                    Connect-SPOService -Url $AdminURL -credential $SPCredentials
                    Set-SPOSite -Identity $siteURL -DefaultLinkToExistingAccess $false
                    Disconnect-SPOService

                    Set-PnPSite -Identity $siteURL -DefaultSharingLinkType $defaultSharingLinkTypeOption
                } elseif ($defaultSharingLinkTypeOption -eq "ExistingAccess"){     
                    Connect-SPOService -Url $AdminURL -credential $SPCredentials
                    Set-SPOSite -Identity $siteURL -DefaultLinkToExistingAccess $true
                    Disconnect-SPOService
                }
                Write-Verbose -Verbose -Message "Setting default sharing link type to $($defaultSharingLinkTypeOption)"
            }

            #Set the default link permission type 
            if ($eumDefaultLinkPermission){
                 switch ($eumDefaultLinkPermission){
                    'View' {$defaultLinkPermissionOption = "View" ; Break}
                    'Edit' {$defaultLinkPermissionOption = "Edit" ; Break}
                }
                Write-Verbose -Verbose -Message "Setting default link permission to $($defaultLinkPermissionOption)"
                Set-PnPSite -Identity $siteURL -DefaultLinkPermission $defaultLinkPermissionOption  
            }  

            # Set the site collection admin
             if ($SiteCollectionAdministrator -ne "") {
                Add-PnPSiteCollectionAdmin -Owners $SiteCollectionAdministrator -Connection $connSite
            }
            Add-PnPSiteCollectionAdmin -Owners $author -Connection $connSite

            # Add Everyone group if on-prem and Public
            if (-not $IsSharePointOnline -and $publicGroup) {
                Set-PnPWebPermission -User "c:0(.s|true" -AddRole "Read" -Connection $connSite
            }

            # add the requester as an owner of the site's group
            if ($IsSharePointOnline -and ($groupId -ne "00000000-0000-0000-0000-000000000000") -and ($author -ne $SPCredentials.UserName)) {
                AddGroupOwner -groupID $groupId -email $author
            }         

            # add the site to hub site, if it configured
            if ($IsSharePointOnline -and $parentHubSite -and $joinHubSite) {
                Write-Verbose -Verbose -Message "Adding the site ($($siteURL)) to the parent hub site($($parentURL))."
                Add-PnPHubSiteAssociation -Site $siteURL -HubSite $parentURL -Connection $connSite
            }

            if ($pnpSiteTemplate) {
                $retries = 0
                $pnpTemplateApplied = $false
                while (($retries -lt 20) -and ($pnpTemplateApplied -eq $false)) {
                    Write-Verbose -Verbose -Message "Applying template $($pnpSiteTemplate) Please wait..."
                    try {
                        $retries += 1
                        Set-PnPTraceLog -On -Level Debug
                        Apply-PnPProvisioningTemplate -Path $pnpSiteTemplate -Connection $connSite -ErrorAction Stop
                        $pnpTemplateApplied = $true
                    }
                    catch {      
                        Write-Verbose -Verbose -Message "Failed applying PnP template."
                        Write-Verbose -Verbose -Message $_
                        Start-Sleep -Seconds 30
                    }
                }
            }
            
            # Create the team if needed
            if ($IsSharePointOnline -and $eumCreateTeam) {
                $team = $null
                $retries = 0

                $teamsConnection = Connect-MicrosoftTeams -Credential $SPCredentials
                while (($retries -lt 20) -and ($team -eq $null)) {
                    try {
                        $retries += 1
                        
                        Write-Verbose -Verbose -Message "Creating Microsoft Team"
                        $team = New-Team -GroupId $groupId
                        $teamsChannels = Get-TeamChannel -GroupId $groupId
                        $generalChannel = $teamsChannels | Where-Object { $_.DisplayName -eq 'General' }
                        $generalChannelId = $generalChannel.Id
                    }
                    catch {      
                        Write-Verbose -Verbose -Message "Failed creating Microsoft Team."
                        Write-Verbose -Verbose -Message $_
                        Start-Sleep -Seconds 30
                    }
                }
                Disconnect-MicrosoftTeams

                Write-Verbose -Verbose -Message "groupId = $($groupId), generalChannelId = $($generalChannelId)"
                AddTeamsChannelRequestFormToChannel -groupId $groupId -teamsChannelId $generalChannelId

                if ($eumCreateOneNote) {
                    AddOneNoteTeamsChannelTab -groupId $groupId -channelName 'General' -teamsChannelId $generalChannelId -siteURL $siteURL
                }

                if ($eumCreatePlanner) {
                    $planId = AddTeamPlanner -groupId $groupId -planTitle "$($siteTitle) Planner"
                    AddPlannerTeamsChannelTab -groupId $groupId -planTitle "$($siteTitle) Planner" -planId $planId -channelName 'General' -teamsChannelId $generalChannelId  
                }
            }

            # Set the breadcrumb HTML
            [string]$breadcrumbHTML = GetBreadcrumbHTML -siteURL $siteURL -siteTitle $siteTitle -parentURL $parentURL

            # Provision the Site Metadata list in the newly created site and add the entry
            $siteMetadataPnPTemplate = "$pnpTemplatePath\EUMSites.SiteMetadataList.xml"
            # Only do this if the template exists.  It is not required if security trimmed A-Z sites list is not needed
            if (Test-Path $siteMetadataPnPTemplate) {
                $connSite = Helper-Connect-PnPOnline -Url $siteURL
                $retries = 0
                $pnpTemplateApplied = $false
                while (($retries -lt 20) -and ($pnpTemplateApplied -eq $false)) {
                    Write-Verbose -Verbose -Message "Importing Site Metadata list with PnPTemplate $($siteMetadataPnPTemplate)"
                    try {
                        $retries += 1
                        Apply-PnPProvisioningTemplate -Path $siteMetadataPnPTemplate -Connection $connSite -ErrorAction Stop

                        [hashtable]$newListItemValues = @{ }

                        $newListItemValues.Add("Title", $siteTitle)
                        $newListItemValues.Add("EUMAlias", $alias)
                        $newListItemValues.Add("EUMDivision", $Division)
                        $newListItemValues.Add("EUMGroupSummary", $groupSummary)
                        $newListItemValues.Add("EUMParentURL", $parentURL)
                        $newListItemValues.Add("SitePurpose", $sitePurpose)
                        $newListItemValues.Add("EUMSiteTemplate", $eumSiteTemplate)
                        $newListItemValues.Add("EUMSiteURL", $siteURL)
                        $newListItemValues.Add("EUMSiteVisibility", $siteVisibility)
                        $newListItemValues.Add("EUMSiteCreated", [System.DateTime]::Now)
                        $newListItemValues.Add("EUMIsSubsite", $false)
                        $newListItemValues.Add("EUMBreadcrumbHTML", $breadcrumbHTML)

                        [Microsoft.SharePoint.Client.ListItem]$spListItem = Add-PnPListItem -List "Site Metadata" -Values $newListItemValues -Connection $connSite
                        $pnpTemplateApplied = $true
                    }
                    catch {      
                        Write-Verbose -Verbose -Message "Failed applying PnP template."
                        Write-Verbose -Verbose -Message $_
                        Start-Sleep -Seconds 30
                    }
                }
            }
            
            # Reconnect to the master site and update the site collection list
            $connLandingSite = Helper-Connect-PnPOnline -Url $SitesListSiteURL

            # Set the breadcrumb and site URL
            [Microsoft.SharePoint.Client.ListItem]$spListItem = Set-PnPListItem -List $SiteListName -Identity $pendingSite.Id -Values @{ "EUMBreadcrumbHTML" = $breadcrumbHTML; "EUMSiteURL" = $siteURL; "EUMParentURL" = $parentURL } -Connection $connLandingSite
        }
    }
    else {
        Write-Verbose -Verbose -Message "No sites pending creation"
    }

    return $True
}

function CreateTeamChannel () {
    Param
    (
        [Parameter (Mandatory = $true)][int]$listItemID
    )

    try {
        Write-Verbose -Verbose -Message "Retrieving teams channel request details for listItemID $($listItemID)..."
        $connLandingSite = Helper-Connect-PnPOnline -Url $SitesListSiteURL
        $channelDetails = Get-PnPListItem -List $TeamsChannelsListName -Id $listItemID -Fields "ID", "Title", "IsPrivate", "Description", "TeamSiteURL", "Description", "CreateOneNoteSection", "CreateChannelPlanner", "ChannelTemplate" -Connection $connLandingSite

        [string]$channelName = $channelDetails["Title"]
        [boolean]$isPrivate = $channelDetails["IsPrivate"]
        [string]$siteURL = $channelDetails["TeamSiteURL"]
        [string]$channelDescription = $channelDetails["Description"]
        [boolean]$createOneNote = $channelDetails["CreateOneNoteSection"]
        [boolean]$createPlanner = $channelDetails["CreateChannelPlanner"]
        [string]$channelTemplateId = $channelDetails["ChannelTemplate"].LookupId

        Disconnect-PnPOnline

        # Get the Office 365 Group ID
        Write-Verbose -Verbose -Message "Retrieving group ID for site $($siteURL)..."
        $connAdmin = Helper-Connect-PnPOnline -Url $AdminURL
        $spSite = Get-PnPTenantSite -Url $siteURL -Connection $connAdmin
        $groupId = $spSite.GroupId
        Disconnect-PnPOnline
    }
    catch {
        Write-Error "Failed retrieving information for listItemID $($listItemID)"
        Write-Error $_
        return $false    
    }


    try {
        # Create the new channel in Teams
        Write-Verbose -Verbose -Message "Creating channel $($channelName)..."
        $teamsConnection = Connect-MicrosoftTeams -Credential $SPCredentials
        $teamsChannel = New-TeamChannel -GroupId $groupId -DisplayName $channelName -Description $channelDescription
        $teamsChannelId = $teamsChannel.Id
        Disconnect-MicrosoftTeams

        if ($createOneNote) {
            Write-Verbose -Verbose -Message "Configuring OneNote for $($channelName)..."
            AddOneNoteTeamsChannelTab -groupId $groupId -channelName $channelName -teamsChannelId $teamsChannelId -siteURL $siteURL
        }

        if ($createPlanner) {
            Write-Verbose -Verbose -Message "Creating Planner for $($channelName)..."
            $planId = AddTeamPlanner -groupId $groupId -planTitle "$($channelName) Planner"
            AddPlannerTeamsChannelTab -groupId $groupId -planTitle "$($channelName) Planner" -planId $planId -channelName $channelName -teamsChannelId $teamsChannelId          
        }

        # Apply implementation specific customizations
        ApplyChannelCustomizations -listItemID $listItemID

        # update the SP list with the ChannelCreationDate
        Write-Verbose -Verbose -Message "Updating ChannelCreationDate..."

        $connLandingSite = Helper-Connect-PnPOnline -Url $SitesListSiteURL

        $spListItem = Set-PnPListItem -List $TeamsChannelsListName -Identity $listItemID -Values @{"ChannelCreationDate" = (Get-Date) } -Connection $connLandingSite
        Disconnect-PnPOnline
    }
    catch {
        Write-Error "Failed creating teams channel $($channelName)"
        Write-Error $_
        return $false   
    }
}

function Check-RunbookLock {
    [String] $ServicePrincipalConnectionName = 'AzureRunAsConnection'
    $AutomationAccountName = Get-AutomationVariable -Name 'AutomationAccountName'
    $ResourceGroupName = Get-AutomationVariable -Name 'ResourceGroupName'
    $AutomationJobID = $PSPrivateMetadata.JobId.Guid

    Write-Verbose "Set-RunbookLock Job ID: $AutomationJobID"

    $ServicePrincipalConnection = Get-AutomationConnection -Name $ServicePrincipalConnectionName   
    if (!$ServicePrincipalConnection) {
        $ErrorString = 
        @"
        Service principal connection $ServicePrincipalConnectionName not found.  Make sure you have created it in Assets. 
        See http://aka.ms/runasaccount to learn more about creating Run As accounts. 
"@
        throw $ErrorString
    }  	
    
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $ServicePrincipalConnection.TenantId `
        -ApplicationId $ServicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint | Write-Verbose

    # Get the information for this job so we can retrieve the Runbook Id
    $CurrentJob = Get-AzureRmAutomationJob -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Id $AutomationJobID
    Write-Verbose "Set-RunbookLock AutomationAccountName: $($CurrentJob.AutomationAccountName)"
    Write-Verbose "Set-RunbookLock RunbookName: $($CurrentJob.RunbookName)"
    Write-Verbose "Set-RunbookLock ResourceGroupName: $($CurrentJob.ResourceGroupName)"
    
    $AllJobs = Get-AzureRmAutomationJob -AutomationAccountName $CurrentJob.AutomationAccountName `
        -ResourceGroupName $CurrentJob.ResourceGroupName `
        -RunbookName $CurrentJob.RunbookName | Sort-Object -Property CreationTime, JobId | Select-Object -Last 10

    foreach ($job in $AllJobs) {
        Write-Verbose "JobID: $($job.JobId), CreationTime: $($job.CreationTime), Status: $($job.Status)"
    }

    $AllActiveJobs = Get-AzureRmAutomationJob -AutomationAccountName $CurrentJob.AutomationAccountName `
        -ResourceGroupName $CurrentJob.ResourceGroupName `
        -RunbookName $CurrentJob.RunbookName | Where -FilterScript { ($_.Status -ne "Completed") `
            -and ($_.Status -ne "Failed") `
            -and ($_.Status -ne "Stopped") } 

    Write-Verbose "AllActiveJobs.Count $($AllActiveJobs.Count)"

    # If there are any active jobs for this runbook, return false. If this is the only job
    # running then return true
    If ($AllActiveJobs.Count -gt 1) {
        # In order to prevent a race condition (although still possible if two jobs were created at the 
        # exact same time), let this job continue if it is the oldest created running job
        $OldestJob = $AllActiveJobs | Sort-Object -Property CreationTime, JobId | Select-Object -First 1
        Write-Verbose "AutomationJobID: $($AutomationJobID), OldestJob.JobId: $($OldestJob.JobId)"

        # If this job is not the oldest created job we will suspend it and let the oldest one go through.
        # When the oldest job completes it will call Set-RunbookLock to make sure the next-oldest job for this runbook is resumed.
        if ($AutomationJobID -ne $OldestJob.JobId) {
            Write-Verbose "Returning false as there is an older currently running job for this runbook already"
            return $false
        }
        else {
            Write-Verbose "Returning true as this is the oldest currently running job for this runbook"
            return $true
        }
    }
    Else {
        Write-Verbose "No other currently running jobs for this runbook"
        return $true
    }
}