# variation on https://dev.to/vishnumohanrk/wsl-port-forwarding-2e22?fbclid=IwAR0GgGeDrtfzgExZTB8U3J8JqP-xtO-ZrpkajVO6sEU8qiI9-OKQFS5sGbE

# restart as admin if not elevated
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) 
{   
  $arguments = "& '" + $myinvocation.mycommand.definition + "'"
  Start-Process powershell -Verb runAs -ArgumentList $arguments
  break
}

# get the IP of the WSL endpoint
$wslIP = Get-HnsEndpoint -EA SilentlyContinue | Where-Object VirtualNetworkName -eq WSL | ForEach-Object IPAddress

if (-NOT $wslIP)
{
    # start the default WSL distro
    Start-Process wsl

    # wait for the IP to show up
    $startTime = Get-Date

    do
    {
        Start-Sleep 3
        $wslIP = Get-HnsEndpoint | Where-Object VirtualNetworkName -eq WSL | ForEach-Object IPAddress
    } until ($wslIP -or $startTime.AddMinutes(3) -lt (Get-Date) )

    if (-NOT $wslIP)
    {
        return (Write-Error "Failed to find the WSL IP address. Please make sure the WSL2 distro is running and has an IP." -EA Stop)
    }
}

# create port proxy rules
$ports = @(5001, 19000, 19001);

netsh interface portproxy reset

$script:firewallRuleNames = @()

$ports | & { process {
        $script:firewallRuleNames += "PortProxy_$_-$wslIP"
        try 
        {
            netsh interface portproxy add v4tov4 listenport=$_ connectport=$_ connectaddress=$wslIP
            New-NetFirewallRule -Name "PortProxy_$_-$wslIP" -DisplayName "WSL portproxy $_" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $_ -EA Stop
        }
        catch 
        {
            Write-Warning "Error while creating PortProxy or firewall rule."
        }
        
    }
}

netsh interface portproxy show v4tov4

Write-Host @"
Run this command to cleanup the firewall rules:

"$($script:firewallRuleNames -join '","')" | Foreach-Object { Remove-NetFirewallRule -Name `$_ -EA SilentlyContinue }
"@
