
$vhdpath='d:\vmfleet.vhdx'
$admin="Administrator"
$adminpass="Azuretest2103"

function specialize-vhd( $vhdpath )
{

    if ((get-vhd $vhdpath).VhdType -ne 'Fixed' ) {
                                        
        # push dynamic vhd to tmppath and place converted at original
        # note that converting a dynamic will leave a sparse hole on refs
        # this is OK, since the copy will not copy the hole
        $f = gi $vhdpath
        $tmpname = "tmp-$($f.Name)"
        $tmppath = join-path $f.DirectoryName $tmpname
        del -Force $tmppath -ErrorAction SilentlyContinue
        ren $f.FullName $tmpname
    
        write-host -ForegroundColor Yellow "convert $($f.FullName) to fixed via $tmppath"
        convert-vhd -Path $tmppath -DestinationPath $f.FullName -VHDType Fixed
        if (-not $?) {
            ren $tmppath $f.Name
            throw "ERROR: could not convert $($f.fullname) to fixed vhdx"
        }
        
        del $tmppath
    }

    $vhd = (gi $vhdpath)
    $vmspec = $vhd.Directory.Name,$vhd.BaseName -join '+'

    # mount vhd and its largest partition
    $o = Mount-VHD $vhd -NoDriveLetter -Passthru
    if ($o -eq $null) {
        Write-Error "failed mount for $vhdpath"
        return $false
    }
    $p = Get-Disk -number $o.DiskNumber | Get-Partition | sort -Property size -Descending | select -first 1
    $p | Add-PartitionAccessPath -AccessPath Z:

    $ok = apply-specialization Z:

    Remove-PartitionAccessPath -AccessPath Z: -InputObject $p
    Dismount-VHD -DiskNumber $o.DiskNumber

    return $ok
}



function apply-specialization( $path )
{
    # all steps here can fail immediately without cleanup

    # error accumulator
    $ok = $true

    # create run directory

    del -Recurse -Force z:\run -ErrorAction SilentlyContinue
    mkdir z:\run
    $ok = $ok -band $?
    if (-not $ok) {
        Write-Error "failed run directory creation for $vhdpath"
        return $ok
    }

    # autologon
    $null = reg load 'HKLM\tmp' z:\windows\system32\config\software
    $ok = $ok -band $?
    $null = reg add 'HKLM\tmp\Microsoft\Windows NT\CurrentVersion\WinLogon' /f /v DefaultUserName /t REG_SZ /d $admin
    $ok = $ok -band $?
    $null = reg add 'HKLM\tmp\Microsoft\Windows NT\CurrentVersion\WinLogon' /f /v DefaultPassword /t REG_SZ /d $adminpass
    $ok = $ok -band $?
    $null = reg add 'HKLM\tmp\Microsoft\Windows NT\CurrentVersion\WinLogon' /f /v AutoAdminLogon /t REG_DWORD /d 1
    $ok = $ok -band $?
    $null = reg add 'HKLM\tmp\Microsoft\Windows NT\CurrentVersion\WinLogon' /f /v Shell /t REG_SZ /d 'powershell.exe -noexit -command c:\users\administrator\launch.ps1'
    $ok = $ok -band $?
    $null = [gc]::Collect()
    $ok = $ok -band $?
    $null = reg unload 'HKLM\tmp'
    $ok = $ok -band $?
    if (-not $ok) {
        Write-Error "failed autologon injection for $vhdpath"
        return $ok
    }

    # scripts

    copy -Force \\SOFS\VMfleet\collect\control\master.ps1 z:\run\master.ps1
    $ok = $ok -band $?
    if (-not $ok) {
        Write-Error "failed injection of specd master.ps1 for $vhdpath"
        return $ok
    }

    del -Force z:\users\administrator\launch.ps1 -ErrorAction SilentlyContinue
    #gc C:\collect\control\launch-template.ps1 |% { $_ -replace '__CONNECTUSER__',$using:connectuser -replace '__CONNECTPASS__',$using:connectpass } > z:\users\administrator\launch.ps1
    Copy \\SOFS\VMFleet\collect\control\launch.ps1 z:\users\administrator\launch.ps1
    $ok = $ok -band $?
    if (-not $ok) {
        Write-Error "failed injection of launch.ps1 for $vhdpath"
        return $err
    }

    echo $vmspec > z:\vmspec.txt
    $ok = $ok -band $?
    if (-not $ok) {
        Write-Error "failed injection of vmspec for $vhdpath"
        return $ok
    }

    # load files
    $f = 'z:\run\testfile1.dat'
    if (-not (gi $f -ErrorAction SilentlyContinue)) {
        fsutil file createnew $f (10GB)
        $ok = $ok -band $?
        fsutil file setvaliddata $f (10GB)
        $ok = $ok -band $?
    }
    if (-not $ok) {
        Write-Error "failed creation of initial load file for $vhdpath"
        return $ok
    }

    return $ok
}


specialize-vhd($vhdpath)