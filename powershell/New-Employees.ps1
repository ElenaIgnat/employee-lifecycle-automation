param(
    [string]$CsvPath = ".\data\new-users.csv",
    [string]$DomainName = "corp.local",
    [switch]$SimulationMode
)

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = ".\logs\onboarding-$Timestamp.log"
$ReportFile = ".\reports\onboarding-$Timestamp.csv"

$Results = @()

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"

    Write-Host $Line

    if (-not (Test-Path ".\logs")) {
        New-Item -ItemType Directory -Path ".\logs" | Out-Null
    }

    Add-Content -Path $LogFile -Value $Line
}

function Add-Result {
    param(
        [string]$Username,
        [string]$Status,
        [string]$Message
    )

    $script:Results += [PSCustomObject]@{
        Username = $Username
        Status   = $Status
        Message  = $Message
    }
}

if (-not (Test-Path ".\reports")) {
    New-Item -ItemType Directory -Path ".\reports" | Out-Null
}

Write-Log "Starting employee onboarding process."

if ($SimulationMode) {
    Write-Log "Simulation mode enabled. No Active Directory changes will be made." "WARNING"
}
else {
    Import-Module ActiveDirectory -ErrorAction Stop
}

if (-not (Test-Path $CsvPath)) {
    Write-Log "CSV file not found: $CsvPath" "ERROR"
    exit 1
}

$Users = Import-Csv $CsvPath

foreach ($User in $Users) {

    Write-Log "Processing user: $($User.Username)"

    try {

        if (
            [string]::IsNullOrWhiteSpace($User.FirstName) -or
            [string]::IsNullOrWhiteSpace($User.LastName) -or
            [string]::IsNullOrWhiteSpace($User.Username) -or
            [string]::IsNullOrWhiteSpace($User.OU)
        ) {
            throw "Missing mandatory user data."
        }

        $Groups = $User.Groups -split ";"

        if ($SimulationMode) {

            $DisplayName = "$($User.FirstName) $($User.LastName)"
            $UPN = "$($User.Username)@$DomainName"

            Write-Log "SIMULATION: Would create user $DisplayName"
            Write-Log "SIMULATION: Username = $($User.Username)"
            Write-Log "SIMULATION: UPN = $UPN"
            Write-Log "SIMULATION: Department = $($User.Department)"
            Write-Log "SIMULATION: Title = $($User.Title)"
            Write-Log "SIMULATION: OU = $($User.OU)"

            foreach ($Group in $Groups) {
                if (-not [string]::IsNullOrWhiteSpace($Group)) {
                    Write-Log "SIMULATION: Would add $($User.Username) to group $Group"
                }
            }

            Add-Result `
                -Username $User.Username `
                -Status "Simulated" `
                -Message "User validated successfully"

            continue
        }

        $ExistingUser = Get-ADUser `
            -Filter "SamAccountName -eq '$($User.Username)'" `
            -ErrorAction SilentlyContinue

        if ($ExistingUser) {

            Write-Log "User $($User.Username) already exists. Skipping." "WARNING"

            Add-Result `
                -Username $User.Username `
                -Status "Skipped" `
                -Message "User already exists"

            continue
        }

        $OUExists = Get-ADOrganizationalUnit `
            -Identity $User.OU `
            -ErrorAction SilentlyContinue

        if (-not $OUExists) {
            throw "OU does not exist: $($User.OU)"
        }

        foreach ($Group in $Groups) {

            if ([string]::IsNullOrWhiteSpace($Group)) {
                continue
            }

            $GroupExists = Get-ADGroup `
                -Identity $Group `
                -ErrorAction SilentlyContinue

            if (-not $GroupExists) {
                throw "Group does not exist: $Group"
            }
        }

        $Password = Read-Host `
            "Enter temporary password for $($User.Username)" `
            -AsSecureString

        $DisplayName = "$($User.FirstName) $($User.LastName)"
        $UPN = "$($User.Username)@$DomainName"

        New-ADUser `
            -Name $DisplayName `
            -GivenName $User.FirstName `
            -Surname $User.LastName `
            -DisplayName $DisplayName `
            -SamAccountName $User.Username `
            -UserPrincipalName $UPN `
            -Department $User.Department `
            -Title $User.Title `
            -Path $User.OU `
            -AccountPassword $Password `
            -Enabled $true `
            -ChangePasswordAtLogon $true `
            -ErrorAction Stop

        Write-Log "Created AD user: $($User.Username)"

        foreach ($Group in $Groups) {

            if ([string]::IsNullOrWhiteSpace($Group)) {
                continue
            }

            Add-ADGroupMember `
                -Identity $Group `
                -Members $User.Username `
                -ErrorAction Stop

            Write-Log "Added $($User.Username) to group $Group"
        }

        Add-Result `
            -Username $User.Username `
            -Status "Success" `
            -Message "User created successfully"
    }
    catch {

        Write-Log "Failed processing $($User.Username): $($_.Exception.Message)" "ERROR"

        Add-Result `
            -Username $User.Username `
            -Status "Failed" `
            -Message $_.Exception.Message
    }
}

$Results | Export-Csv `
    -Path $ReportFile `
    -NoTypeInformation `
    -Encoding UTF8

Write-Log "Onboarding process completed."
Write-Log "Report saved to: $ReportFile"