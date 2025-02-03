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
#$azcopy=$meterpath+"\azcopy.exe"
if (-not (Test-Path -Path "$meterpath\Logs")) {
    New-Item -ItemType Directory -Path "$meterpath\Logs"
}
if (-not (Test-Path -Path "$meterpath\Reports")) {
    New-Item -ItemType Directory -Path "$meterpath\Reports"
}
$logfile = $meterpath+"\Logs\KMeter_"+$billingdate+".log"
$exportfile = $meterpath+"\Reports\KMeter_"+$billingdate+".csv"
$transscriptfile = $meterpath+"\Logs\KMeter_transscript_"+$billingdate+".log"
$GLOBAL:LogDebug=$true
Start-Transcript -Path $transscriptfile -Append

################################################
# MAIN
################################################

logwrite "----------START MAIN---------" -tm
logwrite "*** connect to vCloud" -tm
Connect-CIServer -server "vcloud.konverto.eu" -User "vcread" -Password "trv*hfa1fpu7UKU@def"
logwrite "*** get Organisations" -tm
$orgs=Get-Org | Where-Object {$_.description -ne ''}
#var Keys
$keymem="MEMGB"
$keycpu="CPUGHZ"
$keyvm="VMCOUNT"
$keystorage="STORAGEGB"
#var Metrics
$metricmem="7"
$metriccpu="8"
$metricvm="9"
$metricstorage="10"


foreach ($org in $orgs) {
    $orgvmcount, $orgghz, $orgram, $orgstorage = 0, 0, 0, 0
    $orgName=$org.Name
    $orgCustomerID=$org.Description
    logwrite ("Organisation: "+$orgName)
    $vcds=get-org -Name $org.Name | Get-OrgVdc
    foreach ($vcd in $vcds) {
        $orgghz += $vcd.CpuAllocationGhz
        $orgram += $vcd.MemoryAllocationGB
        $orgstorage += $vcd.StorageLimitGB
        $orgvmcount += $vcd.VMMaxCount
    }
    logwrite ("GHZ: "+$orgghz)
    logwrite ("RAM: "+$orgram)
    logwrite ("Storage: "+$orgstorage)
    logwrite ("VMs: "+$orgvmcount)

    logwrite ($metricmem+";"+$orgCustomerID+";"+$date+";"+$billingdate+";"+$orgName+";COUNT;"+$keymem+";"+$orgram+";1") -tm
    logwrite ($metriccpu+";"+$orgCustomerID+";"+$date+";"+$billingdate+";"+$orgName+";COUNT;"+$keycpu+";"+$orgghz+";1") -tm
    logwrite ($metricvm+";"+$orgCustomerID+";"+$date+";"+$billingdate+";"+$orgName+";COUNT;"+$keyvm+";"+$orgvmcount+";1") -tm
    logwrite ($metricstorage+";"+$orgCustomerID+";"+$date+";"+$billingdate+";"+$orgName+";COUNT;"+$keystorage+";"+$orgstorage+";1") -tm
    exportcsv ($metricmem+";"+$orgCustomerID+";"+$date+";"+$billingdate+";"+$orgName+";COUNT;"+$keymem+";"+$orgram+";1") -Encoding UTF8
    exportcsv ($metriccpu+";"+$orgCustomerID+";"+$date+";"+$billingdate+";"+$orgName+";COUNT;"+$keycpu+";"+$orgghz+";1") -Encoding UTF8
    exportcsv ($metricvm+";"+$orgCustomerID+";"+$date+";"+$billingdate+";"+$orgName+";COUNT;"+$keyvm+";"+$orgvmcount+";1") -Encoding UTF8
    exportcsv ($metricstorage+";"+$orgCustomerID+";"+$date+";"+$billingdate+";"+$orgName+";COUNT;"+$keystorage+";"+$orgstorage+";1") -Encoding UTF8
}
disConnect-CIServer -Server "vcloud.konverto.eu" -Confirm:$false
logwrite "copy File with AzCopy" -tm
#& $azcopy copy $exportfile "https://stvmkonmetering001.blob.core.windows.net/meter?st=2023-11-15T13:13:37Z&si=meeter-write&spr=https&sv=2022-11-02&sr=c&sig=fb%2FR2G6fVwa3OX28eikVzDrMDJrR7pTieRMMox%2BXYJE%3D"
logwrite "----------END---------" -tm
Stop-Transcript
