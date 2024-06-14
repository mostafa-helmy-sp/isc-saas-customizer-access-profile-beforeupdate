param (
    $CampaignId,
    $CampaignName = "Access Profile Definition Campaign"
)

$LogDate = Get-Date -UFormat "%Y%m%d"
$LogFile = ".\Logs_$LogDate.log"

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

# Get Certification Item
$SourceOwnerCertificationId = $(Get-IdentityCertifications -Filters "campaign.id eq `"$CampaignId`"").id

LogToFile("Listing the Access Review Items under Certification: [$SourceOwnerCertificationId]")

# Get All Access Review Items within the Certification
$AllAccessReviewItems = Get-IdentityAccessReviewItems -Id "$SourceOwnerCertificationId"

# Prepare a data structure to store all Access Review Item IDs per Reviewer
$AccessReviewItemsPerOwner = @{}
foreach ( $AccessReviewItem in $AllAccessReviewItems ) {
    # Get the Owner ID from the Account attributes
    $AccountId = $AccessReviewItem.accessSummary.entitlement.account.id
    $OwnerId = $(Get-Account -Id $AccountId).attributes.ownerId
    # Get the existing list
    $AccessReviewItems = $AccessReviewItemsPerOwner[$OwnerId]
    if (!$AccessReviewItems) {
        # Create a new list if it does not exist
        $AccessReviewItems = [System.Collections.ArrayList]::new()
    }
    # Add Current Access Review Item ID to the Owner ID
    $AccessReviewItems.Add($AccessReviewItem.id)
    $AccessReviewItemsPerOwner[$OwnerId] = $AccessReviewItems
}

# Start the Reassignment Process
foreach ( $OwnerId in $AccessReviewItemsPerOwner.Keys ) {
    # Get Access Review Items
    $AccessReviewItemIds = $AccessReviewItemsPerOwner[$OwnerId]
    LogToFile("Reassigning [$($AccessReviewItemIds.Count)] Access Review Items for Owner ID: [$OwnerId]")
    # Build the Reassign Item List
    $ItemList = [System.Collections.ArrayList]::new()
    foreach ( $AccessReviewItemId in $AccessReviewItemIds ) {
        $ItemList.Add(@{
                id   = "$AccessReviewItemId"
                type = "ITEM"
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
    Invoke-ReassignIdentityCertifications -Id "$SourceOwnerCertificationId" -ReviewReassign $AccessReviewReassignBody
}

LogToFile("Activating Campaign [$CampaignId] after finishing reassignment")
Start-Campaign -Id "$CampaignId"

LogToFile("##### Ending reassign process ######")