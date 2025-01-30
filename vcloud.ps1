################################################
# LOG MANAGEMENT
################################################
function logwrite
{
Param ([string]$logstring,[Switch]$tm)

    $LogTime = $((get-date).ToString("hh:mm:ss-fff"))
    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    if ($tm){
    $logstring  = $logstring + " : " + $logtime
    }


    Add-content $Logfile -value $logstring

    if ($GLOBAL:LogDebug -eq $true) { write-host "$logstring" }
}

################################################
# LOG MANAGEMENT
################################################

function exportcsv($arg) { 
    $arg | out-file -append $exportfile -Encoding utf8
}

################################################
# ENVIRONMENT
################################################

$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$billingdate=Get-Date $date -Format "yyyy-MM-dd"
#$meterpath = "C:\KMeter"
$meterpath = $PSScriptRoot
$configfile=$meterpath+"\vdi.csv"
#$azcopy=$meterpath+"\azcopy.exe"
$logfile = $meterpath+"\Logs\KMeter_"+$billingdate+".log"
$exportfile = $meterpath+"\Reports\KMeter_VDI_"+$billingdate+".csv"
$transscriptfile = $meterpath+"\Logs\KMeter_transscript_"+$billingdate+".log"
$GLOBAL:LogDebug=$true
#$xaserver="vkdxa01.onrun.loc"
#$xdserver="vkdxd01.onrun.loc"
Start-Transcript -Path $transscriptfile -Append

logwrite "----------START MAIN---------" -tm
logwrite "*** connect to vCloud" -tm
Connect-CIServer -server "vcloud.konverto.eu" -User "vcread" -Password "trv*hfa1fpu7UKU@def"
logwrite "*** get Organisations" -tm
$orgs=Get-Org | Where-Object {$_.description -ne ''}
foreach ($org in $orgs) {
    $orgvmcount, $orgghz, $orgvram, $orgvstorage = 0, 0, 0, 0
    Write-Host $org.Name
    Write-Host $org.Description
    Write-Host ($org.Description -split ";")[0]
    Write-Host ($org.Description -split ";")[1]
    $vcds=get-org -Name $org.Name | Get-OrgVdc
    foreach ($vcd in $vcds) {
        Write-Host $vcd.CpuAllocationGhz
        $orgghz += $vcd.CpuAllocationGhz
        Write-Host $vcd.MemoryAllocationGB
        $orgvram += $vcd.MemoryAllocationGB
        write-host $vcd.StorageLimitGB
        $orgvstorage += $vcd.StorageLimitGB
        write-host $vcd.VMMaxCount
        $orgvmcount += $vcd.VMMaxCount
    }
    Write-Host "GHZ: " $orgghz
    Write-Host "RAM: " $orgvram
    Write-Host  "Storage: " $orgvstorage
    Write-Host "VMs: " $orgvmcount

}
if (-not (Test-Path $configfile))
{
logwrite "ERROR: Exiting Script - File doesn't exist: $configfile"  -tm
Stop-Transcript
exit
}


################################################
# MAIN
################################################

logwrite "*** Import CSV File" -tm
$config=import-Csv -Path $configfile -Delimiter ";" -Encoding UTF8
Add-PSSnapin Citrix.Broker.*

foreach ($customer in $config) {
    $domain = $customer.domain
    $users=@()
    $rds=@()
    Write-Host $customer.description
    logwrite ("---------------------------------------")
    logwrite ("domain "+$domain+" in progress ....") -tm
    $dgsname=$customer.dgname
        $cfil=$customer.filter

    logwrite ("check deliverycontroller "+$xaserver) -tm
    $alldgs=Get-BrokerDesktopGroup -AdminAddress $xaserver -name "*$dgsname*" -InMaintenanceMode $false
    foreach ($alldg in $alldgs) {
        $key="XENAPPUSER"
        $keycount="XENAPPCOUNT"
        $metric="2"
        $metriccount="4"
        $dgname=$alldg.Name
        $dggroups=Get-BrokerAccessPolicyRule -Name "*_ag" -DesktopGroupName $dgname -AdminAddress $xaserver| select -ExpandProperty includedusers| Select-Object Name
        logwrite ("deliverygroup: "+$alldg.Name) -tm
        foreach ($dggroup in $dggroups) {
            $dggroupname=$dggroup.name
            $dggroupname=$dggroupname.Substring($dggroupname.LastIndexOfAny("\")+1)
            Try {
                $members=Get-ADGroup -Identity $dggroupname -Server $customer.domain | Get-ADGroupMember -Recursive | Where-Object {$_.objectClass -eq "user"} | Get-ADUser -properties * | Where {$_.enabled -eq $true -AND $_.distinguishedName -match $cfil -AND $_.SamAccountName -notlike "*kontest*"}
                $users += $members
                $rds += $members
            }
            Catch
            {
                logwrite ($dggroupname+" not a group") -tm
                $members=Get-ADUser -Identity $dggroupname -Server $customer.domain |  Where {$_.enabled -eq $true -AND $_.distinguishedName -match $cfil -AND $_.SamAccountName -notlike "*kontest*"}
                $users += $members
                $rds += $members
            }
        }
    }

    logwrite ("check deliverycontroller "+$xdserver) -tm
    $alldgs=Get-BrokerDesktopGroup -AdminAddress $xdserver -name "*$dgsname*" -InMaintenanceMode $false
    foreach ($alldg in $alldgs) {
        $key="XENDESKUSER"
        $keycount="XENDESKCOUNT"
        $metric="3"
        $metriccount="5"
        $dgname=$alldg.Name
        $dggroups=Get-BrokerAccessPolicyRule -Name "*_ag" -DesktopGroupName $dgname -AdminAddress $xdserver| select -ExpandProperty includedusers| Select-Object Name
        logwrite ("deliverygroup: "+$alldg.Name) -tm
        foreach ($dggroup in $dggroups) {
            $dggroupname=$dggroup.name
            $dggroupname=$dggroupname.Substring($dggroupname.LastIndexOfAny("\")+1)
            Try {
                $members=Get-ADGroup -Identity $dggroupname -Server $customer.domain | Get-ADGroupMember -Recursive | Where-Object {$_.objectClass -eq "user"} | Get-ADUser -properties * | Where {$_.enabled -eq $true -AND $_.distinguishedName -match $cfil -AND $_.SamAccountName -notlike "*kontest*"}
                $users += $members
                if ($alldg.SessionSupport -eq "MultiSession") {$rds += $members}
            }
            Catch
            {
                logwrite ($dggroupname+" not a group") -tm
                $members=Get-ADUser -Identity $dggroupname -Server $customer.domain |  Where {$_.enabled -eq $true -AND $_.distinguishedName -match $cfil -AND $_.SamAccountName -notlike "*kontest*"}
                $users += $members
                if ($alldg.SessionSupport -eq "MultiSession") {$rds += $members}
            }
        }
    }
    $users=$users | Sort -Unique
    logwrite ($metriccount+";"+$customer.customerid+";"+$date+";"+$billingdate+";"+$customer.domain +"/"+$customer.description+";COUNT;"+$keycount+";"+$users.Count+";1") -tm
    exportcsv ($metriccount+";"+$customer.customerid+";"+$date+";"+$billingdate+";"+$customer.description+";COUNT;"+$keycount+";"+$users.Count+";1") -Encoding UTF8
    if ($rds.Count -gt 0) {
        $rds=$rds | Sort -Unique
        logwrite ("6;"+$customer.customerid+";"+$date+";"+$billingdate+";"+$customer.domain +"/"+$customer.description+";COUNT;RDSCOUNT;"+$rds.Count) -tm
        exportcsv ("6;"+$customer.customerid+";"+$date+";"+$billingdate+";"+$customer.description+";COUNT;RDSCOUNT;"+$rds.Count+";1") -Encoding UTF8
    }
    foreach ($user in $Users) {
        logwrite ($metric+";"+$customer.customerid+";"+$date+";"+$billingdate+";"+$customer.domain +"/"+$customer.description+";"+$user.Displayname+";"+$key+";1;1") -tm
        exportcsv ($metric+";"+$customer.customerid+";"+$date+";"+$billingdate+";"+$customer.description+";"+$user.Displayname+" ("+$user.samAccountName+")"+";"+$key+";1;1") -Encoding UTF8
    }

}

logwrite "copy File with AzCopy" -tm
& $azcopy copy $exportfile "https://stvmkonmetering001.blob.core.windows.net/meter?st=2023-11-15T13:13:37Z&si=meeter-write&spr=https&sv=2022-11-02&sr=c&sig=fb%2FR2G6fVwa3OX28eikVzDrMDJrR7pTieRMMox%2BXYJE%3D"
logwrite "----------END---------" -tm
Stop-Transcript
