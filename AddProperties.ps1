#Vars
$vRopsAddress = 'vrops.vMan.ch'
$ScriptPath = (Get-Item -Path ".\" -Verbose).FullName
[DateTime]$NowDate = (Get-date)
[int64]$NowDateEpoc = Get-Date -Date $NowDate.ToUniversalTime() -UFormat %s
$NowDateEpoc = $NowDateEpoc*1000
$MetaImport = "$ScriptPath\metadata.csv"
$cred = Import-Clixml -Path "$ScriptPath\HOME.xml"

$vRopsUser = $cred.GetNetworkCredential().Username
$vRopsPassword = $cred.GetNetworkCredential().Password

#Take all certs.
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
public bool CheckValidationResult(
ServicePoint srvPoint, X509Certificate certificate,
WebRequest request, int certificateProblem) {
return true;
}
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

#Functions

#Lookup Function to get resourceId from VM Name
Function GetObject([String]$vRopsObjName, [String]$vRopsServer, $User, $Password){

$wc = new-object system.net.WebClient
$wc.Credentials = new-object System.Net.NetworkCredential($User, $Password)
[xml]$Checker = $wc.DownloadString("https://$vRopsServer/suite-api/api/resources?name=$vRopsObjName")

# Check if we get more than 1 result and apply some logic
If ([Int]$Checker.resources.pageInfo.totalCount -gt '1') {

$DataReceivingCount = $Checker.resources.resource.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'

If ($DataReceivingCount.count -gt 1){
$CheckerOutput = ''
return $CheckerOutput
}

}
$CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Checker.resources.resource.identifier; resourceKindKey=$Checker.resources.resource.resourceKey.resourceKindKey}
return $CheckerOutput
}

#Import Metadata into a PSObject / table

$AttributeImport = Import-csv $MetaImport

#Create XML, lookup resourceId and push Data to vRops

ForEach($VM in $AttributeImport){

#Create XML Structure and populate variables from the Metadata file

$XMLFile = @('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ops:property-contents xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">
<ops:property-content statKey="VMAN|FUNCTION">
<ops:timestamps>{0}</ops:timestamps>
<ops:values>{1}</ops:values>
</ops:property-content>
<ops:property-content statKey="VMAN|COSTCODE">
<ops:timestamps>{0}</ops:timestamps>
<ops:values>{2}</ops:values>
</ops:property-content>
<ops:property-content statKey="VMAN|CRITICALITY">
<ops:timestamps>{0}</ops:timestamps>
<ops:values>{3}</ops:values>
</ops:property-content>
</ops:property-contents>' -f $NowDateEpoc,
$VM.FUNCTION,
$VM.COSTCODE,
$VM.CRITICALITY
)

[xml]$xmlSend = $XMLFile

#Run the function to get the resourceId from the VM Name
$resourceLookup = GetObject $VM.NAME $vRopsAddress $vRopsUser $vRopsPassword

#Create URL string for Invoke-RestMethod
$urlsend = 'https://' + $vRopsAddress + '/suite-api/api/resources/'+ $resourceLookup.resourceId + '/properties'

## Debug
echo $urlsend

#Send Attribute data to vRops.
$ContentType = "application/xml;charset=utf-8"
Invoke-RestMethod -Method POST -uri $urlsend -Body $xmlSend -Credential $cred -ContentType $ContentType

#CleanUp Variables to make sure we dont update the next object with the same data as the previous one.
Remove-Variable urlsend -ErrorAction SilentlyContinue
Remove-Variable xmlSend -ErrorAction SilentlyContinue
Remove-Variable XMLFile -ErrorAction SilentlyContinue
}