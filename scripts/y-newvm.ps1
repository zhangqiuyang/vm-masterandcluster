param(
[string]$path="\\SOFS\vmfleet",
[int]$vms=2,
[int]$snodes=3,
[string]$basevhd="\\SOFS\vmfleet1\vmfleet.vhdx"
)

$nodes=Get-ClusterNode | ? State -eq "UP"

icm $nodes {

    if (-not (Get-VMSwitch -Name Internal -ErrorAction SilentlyContinue)) {
    
        New-VMSwitch -name Internal -SwitchType Internal
        Get-NetAdapter |? DriverDescription -eq 'Hyper-V Virtual Ethernet Adapter' |? Name -eq 'vEthernet (Internal)' | New-NetIPAddress -PrefixLength 16 -IPAddress '169.254.1.1'
    }
} | ft -AutoSize



foreach ($vm in 1..$vms) {
    
    $nodename=$env:COMPUTERNAME
	
	foreach ($snode in 1..$snodes) {

        $vmname="vmfleet-$nodename-STNode$snode-$vm"
        $realpath="$path$snode\$vmname"
        
        mkdir $realpath
        cp $basevhd "$realpath\$vmname.vhdx"
        
        Write-Host -ForegroundColor Yellow "$realpath\$vmname.vhdx"
        
        
        $o=new-vm -VHDPath "$realpath\$vmname.vhdx" -Generation 2 -SwitchName Internal -Path $realpath -Name $vmname
        $o|set-vm -ProcessorCount 1 -MemoryStartupBytes 1.75GB -StaticMemory
        $o|Get-VMNetworkAdapter| Set-VMNetworkAdapter -NotMonitoredInCluster $true
        $o | Add-ClusterVirtualMachineRole
        Set-ClusterOwnerNode -Group $o.VMName -Owners $nodename
	}
   
}

