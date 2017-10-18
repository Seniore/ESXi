$ESXiHost = '10.0.0.135'
$ESXiUser = 'root'
$ESXiPass = 'VMware1!'

$newIP = '10.0.0.135'
$newGW = '10.0.0.111'
$newNM = '255.255.255.0'
$DNSServers = @('8.8.8.8','8.8.4.4')
$vlanID = '1234'
$searchDomain = 'seniore.lab.internal'

if($global:DefaultVIServers.Count -gt 0) { Disconnect-VIServer * -Confirm:$false }
Connect-VIServer -Server $ESXiHost -User $ESXiUser -Password $ESXiPass -WarningAction SilentlyContinue

$ESXCli = Get-EsxCli -VMHost $ESXiHost -V2

$HashTable = $ESXCli.network.ip.interface.ipv4.set.CreateArgs()
$HashTable.interfacename ='vmk0'
$HashTable.type = 'static'
$HashTable.netmask = $newNM
$HashTable.ipv4 = $newIP

$ESXCli.network.ip.interface.ipv4.set.Invoke($HashTable)

############################################
# gateway is being taken over from dhcp
###########################################
<#
$HashTable = $ESXCli.network.ip.route.ipv4.add.CreateArgs()
$HashTable.gateway = $newGW
$HashTable.network = 'default'

$ESXCli.network.ip.route.ipv4.add.Invoke($HashTable)
#>


#############
#DNS
#############

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

#DNS Search Domain
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
$HashTable = $ESXCli.network.vswitch.standard.portgroup.set.CreateArgs()
$HashTable.portgroupname = 'Management Network'
$HashTable.vlanid = $vlanID
$ESXCli.network.vswitch.standard.portgroup.set.Invoke($HashTable)



###########
$HashTable = $ESXCli.network.ip.interface.ipv4.get.CreateArgs()
$HashTable.interfacename ='vmk0'
$ESXCli.network.ip.interface.ipv4.get.Invoke($HashTable)

##############
# Reboot - below part is not tested
##############
$HashTable = $ESXCli.system.maintenanceMode.set.CreateArgs()
$HashTable.enable = $true
$ESXCli.system.maintenanceMode.set.Invoke($HashTable)

$HashTable = $ESXCli.system.shutdown.reboot.CreateArgs()
$HashTable.delay = '60'
$HashTable.reason = 'Disabling IPv6'
$ESXCli.system.shutdown.reboot.Invoke($HashTable)

