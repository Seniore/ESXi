<#
.SYNOPSIS
    Set the IP configuration for an ESXi host

.PARAMETER new
    If you wish to change the DHCP assigned IP to a different one please set this parameter as a flag

.EXAMPLE
 .\configureNetwork.ps1 10.0.0.135

.EXAMPLE
.\configureNetwork.ps1 -ESXiHost 10.0.0.135 -ESXiUser 'root' -ESXiPass 'VMware1!' -new -newIP 10.0.0.143 -newNM 255.255.254.0 -DNSServer '8.8.8.8','8.8.4.4' -SearchDomain seniore.internal
 
 #>

[CmdletBinding(DefaultParametersetName='None')]
Param(
  [Parameter(Mandatory=$True,Position=1)]
   [string]$ESXiHost,
	
   [Parameter(Mandatory=$False)]
   [string]$ESXiUser = 'root',

   [Parameter(Mandatory=$False)]
   [string]$ESXiPass = 'VMware1!',

   [Parameter(Mandatory=$False)]
   [int]$vlanID,

   [Parameter(Mandatory=$False,ParameterSetName='changeIP')]
   [switch]$new,

   [Parameter(Mandatory=$True,ParameterSetName='changeIP')]
   [string]$newIP,

   [Parameter(Mandatory=$True,ParameterSetName='changeIP')]
   [string]$newNM,

   [Parameter(Mandatory=$False)]
   [array]$DNSServers,

   [Parameter(Mandatory=$False)]
   [string]$searchDomain
)

<#
$newIP = '10.0.0.135'
$newNM = '255.255.255.0'
$newGW = '10.0.0.111'

$DNSServers = @('8.8.8.8','8.8.4.4')
$searchDomain = 'seniore.lab.internal'
#>


if($global:DefaultVIServers.Count -gt 0) { Disconnect-VIServer * -Confirm:$false }
Connect-VIServer -Server $ESXiHost -User $ESXiUser -Password $ESXiPass -WarningAction SilentlyContinue

$ESXCli = Get-EsxCli -VMHost $ESXiHost -V2

############
if (!$newIP -or !$newNM) {
    $HashTable = $ESXCli.network.ip.interface.ipv4.get.CreateArgs()
    $HashTable.interfacename ='vmk0'
    $currentSetting = $ESXCli.network.ip.interface.ipv4.get.Invoke($HashTable)
    $newIP = $currentSetting.IPv4Address
    $newNM = $currentSetting.IPv4Netmask
    Write-Host "IP & netmask not specified... Using current values: " $newIP "/" $newNM
}
else {
    Write-Host "Setting a new IP config: " $newIP "/" $newNM
}

$HashTable = $ESXCli.network.ip.interface.ipv4.set.CreateArgs()
$HashTable.interfacename ='vmk0'
$HashTable.type = 'static'
$HashTable.netmask = $newNM
$HashTable.ipv4 = $newIP

$ESXCli.network.ip.interface.ipv4.set.Invoke($HashTable)

if($ESXiHost -ne $newIP) { 
    Write-Host "Reconnecting to the ESXi hosts using the new IP"
    Disconnect-VIServer * -Confirm:$false 
    Connect-VIServer -Server $newIP -User $ESXiUser -Password $ESXiPass -WarningAction SilentlyContinue 
    $ESXCli = Get-EsxCli -VMHost $newIP -V2
    }

#################################################################
# gateway is being taken over from dhcp, no need to change it
#################################################################
<#
$HashTable = $ESXCli.network.ip.route.ipv4.add.CreateArgs()
$HashTable.gateway = $newGW
$HashTable.network = 'default'

$ESXCli.network.ip.route.ipv4.add.Invoke($HashTable)
#>


#############
#DNS
#############

if ($DNSServers) {
    #Clean up any existing entries
    $currentDNS = $ESXCli.network.ip.dns.server.list.Invoke()
    foreach ($dnsHost in $currentDNS.DNSServers) {
        $HashTable = $ESXCli.network.ip.dns.server.remove.CreateArgs()
        $HashTable.server = $dnsHost
        $ESXCli.network.ip.dns.server.remove.Invoke($HashTable)
    }

    #Add new DNS hosts
    foreach ($dnsHost in $DNSServers) {
        $HashTable = $ESXCli.network.ip.dns.server.add.CreateArgs()
        $HashTable.server = $dnsHost
        $ESXCli.network.ip.dns.server.add.Invoke($HashTable)
    }
}

#DNS Search Domain
if($searchDomain) {
    #Clean up any existing entries
    $currentSD = $ESXCli.network.ip.dns.search.list.Invoke()
    foreach ($domain in $currentSD.DNSSearchDomains) {
        $HashTable = $ESXCli.network.ip.dns.search.remove.CreateArgs()
        $HashTable.domain = $domain
        $ESXCli.network.ip.dns.search.remove.Invoke($HashTable)
    }

    #Add new item
    $HashTable = $ESXCli.network.ip.dns.search.add.CreateArgs()
    $HashTable.domain = $searchDomain
    $ESXCli.network.ip.dns.search.add.Invoke($HashTable)
}

###############
# Disable IPv6
###############
$HashTable = $ESXCli.system.module.parameters.set.CreateArgs()
$HashTable.module = 'tcpip4'
$HashTable.parameterstring = 'ipv6=0'
$ESXCli.system.module.parameters.set.Invoke($HashTable)



#############
# VLAN
#############
if($vlanID) {
    $HashTable = $ESXCli.network.vswitch.standard.portgroup.set.CreateArgs()
    $HashTable.portgroupname = 'Management Network'
    $HashTable.vlanid = $vlanID
    $ESXCli.network.vswitch.standard.portgroup.set.Invoke($HashTable)
}


###########


##############
# Reboot - part below is not tested - means my host didn't want to go into MM ;)
##############
<#
$HashTable = $ESXCli.system.maintenanceMode.set.CreateArgs()
$HashTable.enable = $true
$ESXCli.system.maintenanceMode.set.Invoke($HashTable)

$HashTable = $ESXCli.system.shutdown.reboot.CreateArgs()
$HashTable.delay = '60'
$HashTable.reason = 'Disabling IPv6'
$ESXCli.system.shutdown.reboot.Invoke($HashTable)
#>
