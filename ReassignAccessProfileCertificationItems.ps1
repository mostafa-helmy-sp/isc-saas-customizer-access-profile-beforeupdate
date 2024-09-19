param (
    $CampaignId,
    $CampaignName = "Access Profile Definition Campaign",
    $SourceOwnerName = "SailPoint.Workflow",
    $SourceOwnerId = "9e95ffec295143eca85d7d917c3bb3dc"
)

[int]$ReassignLimit = "50"
$LogDate = Get-Date -UFormat "%Y%m%d"
$LogFile = ".\Logs_$LogDate.log"
Set-DefaultConfiguration -MaximumRetryCount 10 -RetryIntervalSeconds 5

#====================-------Helper functions-------====================
function LogToFile([String] $Info) {
    "$(Get-Date -Format "yyyy/MM/dd HH:mm:ss") - $Info" | Out-File $LogFile -Append
}

LogToFile("##### Starting reassign process ######")

# Get the CampaignId if not provided from the default CampaignName
if (!$CampaignId) {
    LogToFile("No Campaign ID passed. Using Campaign Name [$CampaignName] to find Campaign ID")
    $Campaign = Get-ActiveCampaigns -Filters "name eq `"$CampaignName`" and status eq `"STAGED`"" -Sorters "-created"
    # Get the most recently created campaign if more than one exist
    if ($Campaign -is [Array]) {
        $Campaign = $Campaign[0]
    }
    $CampaignId = $Campaign.id
}

# Exit if still no Campaign ID
if (!$CampaignId) {
    LogToFile("Could not find a valid Campaign ID")
    Exit
}

LogToFile("Processing Campaign with ID: [$CampaignId]")

# Get Certification Item of the Default Source Owner
$SourceOwnerCertificationId
$Parameters = @{
    "Filters" = "campaign.id eq `"$CampaignId`""
}
$CertificationItems = Invoke-Paginate -Function "Get-IdentityCertifications" -Increment 250 -Parameters $Parameters
foreach ($CertificationItem in $CertificationItems) {
    if ($CertificationItem.reviewer.id -eq $SourceOwnerId || $CertificationItem.reviewer.name -eq $SourceOwnerName) {
        $SourceOwnerCertificationId = $CertificationItem.id
        Break
    }
}

# Exit if could not find the Source Owner Certificaiton ID
if (!$SourceOwnerCertificationId) {
    LogToFile("Could not find a valid Certification Item ID using Source Owner Name: [$SourceOwnerName] and ID: [$SourceOwnerId]")
    Exit
}

LogToFile("Listing the Certification Summary Items under Certification: [$SourceOwnerCertificationId]")

# Get All Certification Summary Items within the Certification
$Parameters = @{
    "Id" = "$SourceOwnerCertificationId"
}
$AllCertificationSummaryItems = Invoke-Paginate -Function "Get-IdentitySummaries" -Increment 250 -Parameters $Parameters

# Prepare a data structure to store all Access Review Item IDs per Reviewer
$CertificationSummaryItemsPerOwner = @{}
foreach ( $CertificationSummaryItem in $AllCertificationSummaryItems ) {
    # Get the Owner ID from the Account attributes
    $AccessProfileName = $CertificationSummaryItem.name
    $AccessProfile = Get-AccessProfiles -Filters "name eq `"$AccessProfileName`""
    $OwnerId = $AccessProfile.owner.id
    # Get the existing list
    $CertificationSummaryItems = $CertificationSummaryItemsPerOwner[$OwnerId]
    if (!$CertificationSummaryItems) {
        # Create a new list if it does not exist
        $CertificationSummaryItems = [System.Collections.ArrayList]::new()
    }
    # Add Current Access Review Item ID to the Owner ID
    $CertificationSummaryItems.Add($CertificationSummaryItem.id)
    $CertificationSummaryItemsPerOwner[$OwnerId] = $CertificationSummaryItems
}

# Start the Reassignment Process
foreach ( $OwnerId in $CertificationSummaryItemsPerOwner.Keys ) {
    # Get Certification Summary Items
    $CertificationSummaryItemIds = $CertificationSummaryItemsPerOwner[$OwnerId]
    LogToFile("Reassigning [$($CertificationSummaryItemIds.Count)] Certification Summary Items for Owner ID: [$OwnerId]")
    do {
        # Build the Reassign Item List
        $ItemList = [System.Collections.ArrayList]::new()
        $Limit = (@($ReassignLimit, $CertificationSummaryItemIds.Count) | Measure-Object -Minimum).Minimum
        for ( $i = 0; $i -lt $Limit; $i++ ) {
            $CertificationSummaryItemId = $CertificationSummaryItemIds[0]
            $CertificationSummaryItemIds.RemoveAt(0)
            $ItemList.Add(@{
                    id   = "$CertificationSummaryItemId"
                    type = "TARGET_SUMMARY"
                })
        }
        $ItemListJSON = ConvertTo-Json -InputObject $ItemList
        # Build the Reassign Request Body
        $ReassignBody = @"
        {
            "reason":"Reassigning to Access Profile Owner",
            "reassignTo":"$OwnerId",
            "reassign": $ItemListJSON
        }
"@
        $AccessReviewReassignBody = ConvertFrom-JsonToAccessReviewReassignment -Json $ReassignBody
        # Reassign Items for the current Owner
        try {
            Invoke-ReassignIdentityCertifications -Id "$SourceOwnerCertificationId" -ReviewReassign $AccessReviewReassignBody
        }
        catch {
            LogToFile("Error Reassigning [$($ItemList.Count)] Certification Summary Items for Owner ID: [$OwnerId]!")
        }
    }
    while ($CertificationSummaryItemIds.Count -gt "0")
}

# Wait 10 seconds then activate the campaign
Start-Sleep -Seconds 10
LogToFile("Activating Campaign [$CampaignId] after finishing reassignment")
Start-Campaign -Id "$CampaignId"

LogToFile("##### Ending reassign process ######")