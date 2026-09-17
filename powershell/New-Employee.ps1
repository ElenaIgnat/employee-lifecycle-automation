param(
    [string]$CsvPath = ".\data\new-users.csv",
    [string]$DomainName = "corp.local"
)

Import-Module ActiveDirectory

$Users = Import-Csv $CsvPath

foreach ($User in $Users) {

    Write-Host "Processing user: $($User.Username)"

    $ExistingUser = Get-ADUser `
        -Filter "SamAccountName -eq '$($User.Username)'" `
        -ErrorAction SilentlyContinue

    if ($ExistingUser) {
        Write-Host "User $($User.Username) already exists. Skipping."
        continue
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
        -ChangePasswordAtLogon $true

    Write-Host "Created user: $($User.Username)"

    $Groups = $User.Groups -split ";"

    foreach ($Group in $Groups) {

        if ([string]::IsNullOrWhiteSpace($Group)) {
            continue
        }

        Add-ADGroupMember `
            -Identity $Group `
            -Members $User.Username

        Write-Host "Added $($User.Username) to $Group"
    }

    $CreatedUser = Get-ADUser `
        -Identity $User.Username `
        -Properties Department,Title,MemberOf

    Write-Host "Validation completed for $($User.Username)"
}
