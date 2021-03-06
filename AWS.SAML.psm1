using module .\AWS.SAML.Browser.psm1
using module .\AWS.SAML.Settings.psm1
using module .\AWS.SAML.Utils.psm1
using module .\AWS.SAML.Profile.psm1

<#
    .SYNOPSIS
        Get AWS STS credentials for using in the CLI from a SAML based login.

    .DESCRIPTION
        Get AWS STS credentials for using in the CLI from a SAML based login.

    .EXAMPLE
        C:\PS> Login-AWSSAML

    .PARAMETER InitURL
        The SAML Login Initiation URL.  If not passed you will be prompted and it will be saved for future use.

    .PARAMETER Browser
        Choose the browser to handle the login process.  Options: Chrome, Firefox, Edge, IE  Default: Chrome

    .PARAMETER ProfileName
        When specified the credentials are saved as an AWS profile under the specified name for use in the CLI

    .PARAMETER SessionDuration
        When specified your role session lasts for the specified duration in seconds. By default, the value is set to 3600 seconds.
#>
function New-AWSSAMLLogin {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
    [Alias('Login-AWSSAML','las')]
    param(
        [String]$InitURL,
        [ValidateSet('Chrome', 'Firefox', 'Edge', 'IE')]
        [String]$Browser = 'Chrome',
        [Switch]$NoBrowserProfile,
        [Alias('Profile')]
        [String]$ProfileName,
        [Int]$SessionDuration = 3600
    )
    if ($pscmdlet.ShouldProcess('AWS SAML', 'login'))
    {
        if([String]::IsNullOrWhiteSpace($InitURL)){
            $InitURL = Get-AWSSAMLURL
        }

        # Start Browser for Login
        $driver = Start-Browser -InitURL $InitURL -Browser $Browser -NoProfile:$NoBrowserProfile

        # Get SAML Assertion
        $samlAssertion = Get-SAMLAssertion -Driver $driver

        # Get Selected Role
        $consoleData = Get-ConsoleData -Driver $driver

        # Close Browser
        $Driver.quit()

        # Clear Screen
        Clear-Host

        # Get Role Details from SAML
        $arns = Get-SAMLRole -Assertion $samlAssertion -AccountID $consoleData.AccountID -Role $consoleData.Role

        # Get STS Credentials with SAML
        $sts = Use-STSRoleWithSAML -PrincipalArn $arns.PrincipalArn -RoleArn $arns.RoleArn -SAMLAssertion $samlAssertion -DurationInSeconds $SessionDuration

        # Store Credentials for use
        if($ProfileName){
            # Store in Profile
            Set-AWSProfile -ProfileName $ProfileName -AccessKeyId $sts.Credentials.AccessKeyId -SecretAccessKey $sts.Credentials.SecretAccessKey -SessionToken $sts.Credentials.SessionToken -AccountID $consoleData.AccountID -Role $consoleData.Role -SessionDuration $SessionDuration
        }else{
            # Store in Environment Variable
            Add-AWSSTSCred -STS $sts
        }

        # Output Console Data
        return [PSCustomObject]@{
            Account = $consoleData.Alias
            AccountID = $consoleData.AccountID
            User = $consoleData.Name
            Role = $consoleData.Role
            Expires = $sts.Credentials.Expiration
        }
    }
}

<#
    .SYNOPSIS
        Update saved profiles with new STS Credentials from SAML based login.

    .DESCRIPTION
        Update saved profiles with new STS Credentials from SAML based login.  Must have previously saved profiles using `New-AWSSAMLLogin -Profile <name>`

    .EXAMPLE
        C:\PS> Update-AWSSAMLLogin

    .PARAMETER Browser
        Choose the browser to handle the login process.  Options: Chrome, Firefox, Edge, IE  Default: Chrome

    .PARAMETER ProfileName
        When specified the credentials are saved as an AWS profile under the specified name for use in the CLI

    .PARAMETER SessionDuration
        When specified your role session lasts for the specified duration in seconds. By default, the value is set to 3600 seconds.
#>
function Update-AWSSAMLLogin {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
    [Alias('Update-AWSSAML','uas')]
    param(
        [ValidateSet('Chrome', 'Firefox', 'Edge', 'IE')]
        [String]$Browser = 'Chrome',
        [Alias('Profile')]
        [String]$ProfileName,
        [Int]$SessionDuration
    )
    if ($pscmdlet.ShouldProcess('AWS SAML', 'update'))
    {
        $InitURL = Get-AWSSAMLURL

        # Start Browser for Login
        $driver = Start-Browser -InitURL $InitURL -Browser $Browser -Headless

        # Get SAML Assertion
        # TODO: Implement timeout and relaunch of non headless browser for authentication issue detection
        $samlAssertion = Get-SAMLAssertion -Driver $driver

        # Close Browser
        $Driver.quit()

        # Renew each valid profile
        if($ProfileName){
            $profiles = Get-AWSProfile -ProfileName $ProfileName
        }else{
            $profiles = Get-AWSProfile
        }

        foreach ($profile in $profiles) {
            if($profile.AccountID -ne '' -and $profile.Role -ne ''){
                Write-Output "Updating Profile $($profile.Name)"

                # Get Role Details from SAML
                $arns = Get-SAMLRole -Assertion $samlAssertion -AccountID $profile.AccountID -Role $profile.Role
                if($arns){
                    # Allow passed in duration to override profile settings
                    if(!($SessionDuration)){
                        $SessionDuration = $profile.Duration
                    }

                    # Get STS Credentials with SAML
                    $sts = Use-STSRoleWithSAML -PrincipalArn $arns.PrincipalArn -RoleArn $arns.RoleArn -SAMLAssertion $samlAssertion -DurationInSeconds $SessionDuration

                    # Update Profile
                    Set-AWSProfile -ProfileName $profile.Name -AccessKeyId $sts.Credentials.AccessKeyId -SecretAccessKey $sts.Credentials.SecretAccessKey -SessionToken $sts.Credentials.SessionToken -AccountID $profile.AccountID -Role $profile.Role -SessionDuration $profile.Duration
                }
            }
        }
    }
}