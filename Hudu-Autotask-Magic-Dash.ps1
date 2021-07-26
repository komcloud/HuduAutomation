# Add this CSS to Admin -> Design -> Custom CSS
# .custom-fast-fact.custom-fast-fact--warning {
#     background: #f5c086;
# }
#####################################################################
# Get a Hudu API Key from https://yourhududomain.com/admin/api_keys
$HuduAPIKey = 'YourHuduAPIKey'
# Set the base domain of your Hudu instance without a trailing /
$HuduBaseDomain = 'https://your.hudu.domain'
######################### Autotask Settings ###########################
$AutotaskIntegratorID = 'AutotaskIntegratorID'
$AutotaskAPIUser = 'apiuser@domain.com'
$AutotaskAPISecret = 'autotasksecret'
$ExcludeStatus =
$ExcludeType =
$ExcludeQueue =
$AutotaskRoot = 'https://ww16.autotask.net'
$AutoTaskAPIBase = 'https://webservices16.autotask.net'
######################################################################
#### Other Settings ####
$CreateAllOverdueTicketsReport = $true
$globalReportName = 'Autotask - Overdue Ticket Report'
$folderID = 662
$TableStylingGood = '<th>', "<th style=`"background-color:#aeeab4`">"
$TableStylingBad = '<th>', "<th style=`"background-color:#f8d1d3`">"
#####################################################################
function Get-ATFieldHash {
	Param(
		[Array]$fieldsIn,
		[string]$name
	)

	$tempFields = ($fieldsIn.fields | Where-Object -filter { $_.name -eq $name }).picklistValues
	$tempValues = $tempFields | Where-Object -filter { $_.isActive -eq $true } | Select-Object value, label
	$tempHash = @{}
	$tempValues | ForEach-Object { $tempHash[$_.value] = $_.label }

	return $tempHash
}

#Get the Hudu API Module if not installed
if (Get-Module -ListAvailable -Name HuduAPI) {
	Import-Module HuduAPI
} else {
	Install-Module HuduAPI -Force
	Import-Module HuduAPI
}

if (Get-Module -ListAvailable -Name AutotaskAPI) {
	Import-Module AutotaskAPI
} else {
	Install-Module AutotaskAPI -Force
	Import-Module AutotaskAPI
}

$TicketFilter = "{`"filter`":[{`"op`":`"notin`",`"field`":`"queueID`",`"value`":$ExcludeQueue},{`"op`":`"notin`",`"field`":`"status`",`"value`":$ExcludeStatus},{`"op`":`"notin`",`"field`":`"ticketType`",`"value`":$ExcludeType}]}"

#Set Hudu logon information
New-HuduAPIKey $HuduAPIKey
New-HuduBaseUrl $HuduBaseDomain

$headers = @{
	'ApiIntegrationCode' = $AutotaskIntegratorID
	'UserName'           = $AutotaskAPIUser
	'Secret'             = $AutotaskAPISecret
}

$fields = Invoke-RestMethod -Method get -Uri "$AutoTaskAPIBase/ATServicesRest/V1.0/Tickets/entityInformation/fields" `
	-Headers $headers -ContentType 'application/json'


#Get Statuses
$statusValues = Get-ATFieldHash -name 'status' -fieldsIn $fields

if (!$ExcludeStatus) {
	Write-Host "ExcludeStatus not set please exclude your closed statuses at least from below in the format of '[1,5,7,9]'"
	$statusValues | Format-Table
}

#Get Ticket types
$typeValues = Get-ATFieldHash -name 'ticketType' -fieldsIn $fields

if (!$ExcludeType) {
	Write-Host "ExcludeType not set please exclude types from below in the format of '[1,5,7,9]"
	$typeValues | Format-Table
}

#Get Queue Types
$queueValues = Get-ATFieldHash -name 'queueID' -fieldsIn $fields

if (!$ExcludeType) {
	Write-Host "ExcludeQueue not set please exclude types from below in the format of '[1,5,7,9]"
	$queueValues | Format-Table
}

#Get Creator Types
$creatorValues = Get-ATFieldHash -name 'creatorType' -fieldsIn $fields

#Get Issue Types
$issueValues = Get-ATFieldHash -name 'issueType' -fieldsIn $fields

#Get Priority Types
$priorityValues = Get-ATFieldHash -name 'priority' -fieldsIn $fields

#Get Source Types
$sourceValues = Get-ATFieldHash -name 'source' -fieldsIn $fields

#Get Sub Issue Types
$subissueValues = Get-ATFieldHash -name 'subIssueType' -fieldsIn $fields

#Get Categories
$catValues = Get-ATFieldHash -name 'ticketCategory' -fieldsIn $fields


$Creds = New-Object System.Management.Automation.PSCredential($AutotaskAPIUser, $(ConvertTo-SecureString $AutotaskAPISecret -AsPlainText -Force))

Add-AutotaskAPIAuth -ApiIntegrationcode $AutotaskIntegratorID -credentials $Creds

$companies = Get-AutotaskAPIResource -resource Companies -SimpleSearch "isactive eq $true"

$TicketFilter = "{`"filter`":[{`"op`":`"notin`",`"field`":`"queueID`",`"value`":$ExcludeQueue},{`"op`":`"notin`",`"field`":`"status`",`"value`":$ExcludeStatus}]}"
$tickets = Get-AutotaskAPIResource -Resource Tickets -SearchQuery $TicketFilter

$AutotaskExe = '/Autotask/AutotaskExtend/ExecuteCommand.aspx?Code=OpenTicketDetail&TicketNumber='

$GlobalOverdue = New-Object System.Collections.ArrayList

foreach ($company in $companies) {
	$custTickets = $tickets | Where-Object { $_.companyID -eq $company.id } | Select-Object id, ticketNUmber, createdate, title, description, dueDateTime, lastActivityPersonType, lastCustomerVisibleActivityDateTime, priority, source, status, issueType, subIssueType, ticketType
	$outTickets = foreach ($ticket in $custTickets) {
		[PSCustomObject]@{
			'Ticket-Number' =	"<a target=`"_blank`" href=`"$($AutotaskRoot)$($AutotaskExe)$($ticket.ticketNumber)`">$($ticket.ticketNumber)</a>"
			'Created'       =	$ticket.createdate
			'Title'         =	$ticket.title
			'Due'           =	$ticket.dueDateTime
			'Last-Updater'  =	$creatorValues["$($ticket.lastActivityPersonType)"]
			'Last-Update'   =	$ticket.lastCustomerVisibleActivityDateTime
			'Priority'      =	$priorityValues["$($ticket.priority)"]
			'Source'        =	$sourceValues["$($ticket.source)"]
			'Status'        =	$statusValues["$($ticket.status)"]
			'Type'          =	$issueValues["$($ticket.issueType)"]
			'Sub-Type'      =	$subissueValues["$($ticket.subIssueType)"]
			'Ticket-Type'   =	$typeValues["$($ticket.ticketType)"]
			'Company'       =	$company.companyName
		}
	}
	Write-Host "Processing $($company.companyName)" -ForegroundColor green
	if (@($outTickets).count -gt 0) {

		$Now = Get-Date
		$overdue = @($outTickets | Where-Object { $([DateTime]::Parse($_.Due, [cultureinfo]::GetCultureInfo('en-US'))) -lt $now }).count

		$MagicMessage = "$(@($outTickets).count) Open Tickets"


		$shade = 'success'

		if ($overdue -ge 1) {
			$shade = 'warning'
			$MagicMessage = "$overdue / $(@($outTickets).count) Tickets Overdue"
			$overdueTickets = $outTickets | Where-Object { $([DateTime]::Parse($_.Due, [cultureinfo]::GetCultureInfo('en-US'))) -le $now }
			foreach ($odticket in $overdueTickets) { $null = $GlobalOverdue.add($odticket) }
			$outTickets = $outTickets | Where-Object { $([DateTime]::Parse($_.Due, [cultureinfo]::GetCultureInfo('en-US'))) -gt $now }
			$overdueHTML = [System.Net.WebUtility]::HtmlDecode(($overdueTickets | Select-Object 'Ticket-Number', 'Created', 'Title', 'Due', 'Last-Updater', 'Last-Update', 'Priority', 'Source', 'Status', 'Type', 'Sub-Type', 'Ticket-Type' | ConvertTo-Html -Fragment | Out-String) -replace $TableStylingBad)
			$goodHTML = [System.Net.WebUtility]::HtmlDecode(($outTickets | Select-Object 'Ticket-Number', 'Created', 'Title', 'Due', 'Last-Updater', 'Last-Update', 'Priority', 'Source', 'Status', 'Type', 'Sub-Type', 'Ticket-Type' | ConvertTo-Html -Fragment | Out-String) -replace $TableStylingGood)
			$body = "<h2>Overdue Tickets:</h2>$overdueHTML<h2>Tickets:</h2>$goodhtml"

		} else {
			$body = [System.Net.WebUtility]::HtmlDecode(($outTickets | Select-Object 'Ticket-Number', 'Created', 'Title', 'Due', 'Last-Updater', 'Last-Update', 'Priority', 'Source', 'Status', 'Type', 'Sub-Type', 'Ticket-Type' | ConvertTo-Html -Fragment | Out-String) -replace $TableStylingGood)
		}

		if ($overdue -ge 2) {
			$shade = 'danger'
		}


		try {
			$Huduresult = Set-HuduMagicDash -title 'Autotask - Open Tickets' -company_name $(($company.companyName).Trim()) -message $MagicMessage -icon 'fas fa-chart-pie' -content $body -shade $shade -ea stop
			Write-Host 'Magic Dash Set'
		} catch {
			Write-Host "$(($company.companyName).Trim()) not found in Hudu or other error occured"
		}
	} else {
		try {
			$Huduresult = Set-HuduMagicDash -title 'Autotask - Open Tickets' -company_name $(($company.companyName).Trim()) -message 'No Open Tickets' -icon 'fas fa-chart-pie' -shade 'success' -ea stop
			Write-Host 'Magic Dash Set'
		} catch {
			Write-Host "$(($company.companyName).Trim()) not found in Hudu or other error occured"
		}
	}

}

if ($CreateAllOverdueTicketsReport -eq $true) {

	$articleHTML = [System.Net.WebUtility]::HtmlDecode($($GlobalOverdue | Select-Object 'Ticket-Number', 'Company', 'Title', 'Due', 'Last-Update', 'Priority', 'Status' | ConvertTo-Html -Fragment | Out-String))
	$reportdate = Get-Date
	$body = "<h2>Report last updated: $reportDate</h2><figure class=`"table`">$articleHTML</figure>"
	#Check if an article already exists


	$article = Get-HuduArticles -name $globalReportName
	if ($article) {
		$result = Set-HuduArticle -name $globalReportName -content $body -folder_id $folderID -article_id $article.id
		Write-Host 'Updated Global Report'
	} else {
		$result = New-HuduArticle -name $globalReportName -content $body -folder_id $folderID
		Write-Host 'Created Global Report'
	}
}
