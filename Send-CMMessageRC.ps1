[CmdletBinding()]
Param (
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$True)]
   [String] $TemplateName,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $MP,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $SiteCode,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString1,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString2,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString3,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString4,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString5,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString6,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString7,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString8,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString9,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $InsertionString10,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $SMS_ModuleName,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $SMS_MessageID,                                         #'1073781821' is the only messageID I've found this far that prints the InsertionStrings to the description. Must use Module=SMS Provider for this to work.
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]    #The insertionString can however still be used as arguments to a script by using %msgin01-10 in a status  filter rule.
   [string] $MachineName,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $SMS_Component,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   $ExpectReply=$false,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [int] $ReplyTimeout=120,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $ClassName = "SMS_GenericStatusMessage_info"            #You can add more classes by using [Microsoft.ConfigurationManagement.Messaging.StatusMessages.StatusMessageGenerator]::new() _
                                                                    #and saving default props/quals to files named "class"props.txt and "class"quals.txt by using $_.GatherStatusMessageProperties("ClassName") Eg.:  $_.GatherStatusMessageProperties("SMS_GenericStatusMessage_info") 
)

#Fix for calling script with a bool from CMD.
If (($ExpectReply.GetType().ToString()) -eq "System.String")
{
    #write-host "string"
    if ($ExpectReply.ToLower() -eq '$true')
    {
        $ExpectReply=$true
    }
}


$ScriptDir=Split-path $Script:myInvocation.MyCommand.Definition

write-host ""
Add-type -path $ScriptDir\Microsoft.ConfigurationManagement.Messaging.dll

Start-Transcript -Path $env:TEMP\StatusMsg.log -Append

$WinPE=$False
$RunningInTS=$True
$WinPE=test-path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinPE"
$NeedForReg=$False

try
{
	$TsEnv=New-Object -ComObject Microsoft.SMS.TSEnvironment
}
catch
{
	$RunningInTS=$False
}

function WaitForReply ($UniqueURL)
{

$Up = "http://+:8081/$UniqueURL/"
$Hso = New-Object Net.HttpListener

#ignore self-signed/invalid ssl certs
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$True}

Foreach ($P in $Up) {$Hso.Prefixes.Add($P)}

    $Hso.Start()
    #$Hso.AuthenticationSchemes = [System.Net.AuthenticationSchemes]::IntegratedWindowsAuthentication
    While ($Hso.IsListening)  {
        $HC = $Hso.GetContext()
        #$user= $HC.User
        #write-host $user.Identity.Name;
        
        $HReq = $HC.Request
        
        #write-host "Auth:" $Hreq.IsAuthenticated;
        #write-host "";
        #write-host $HReq.Headers.AllKeys
        $HRes = $HC.Response
        #$stream=$HReq.InputStream
        #write-host $stream
        #write-host $HReq.HttpMethod
        #$HRes.Headers.Add("Content-Type","text/html")      
        $Reply = $HReq.QueryString['URL']
        #write-host $HReq.RawUrl
        $Reply+=";$(Get-Date -Format u)"
        #Invoke-RestMethod -uri $ProxURL -Method Post -body $stream -ContentType 'application/json'
        #Write-Host "Recieved Reply."
        #write-host $Reply

        #If ($ProxURL) {$Content = $Wco.downloadString("$ProxURL")}      
        #$Buf = [Text.Encoding]::UTF8.GetBytes($Content)
        #$HRes.ContentLength64 = $Buf.Length
        #$HRes.OutputStream.Write($Buf,0,$Buf.Length)
        $HRes.Close()
        if ($Reply.Contains("quit"))
        {
        #write-host "quit"
        $Hso.Stop()
        }
        
    }
    return $Reply
}



function ImportFakeCert
{
    write-host "Importing fake certificate..."
#    $SignCert = [Microsoft.ConfigurationManagement.Messaging.Framework.MessageCertificateX509File]::CreateAndStoreSelfSignedCertificate(
#    "SCCM Fake Signing Certificate",
#    "Fake SignCert",
#    "My",
#    "LocalMachine",
#    @('2.5.29.37'),
#    (Get-Date).AddMinutes(-10),
#    (Get-Date).AddYears(5)
#    )

$SignCert= [Microsoft.ConfigurationManagement.Messaging.Framework.MessageCertificateX509Volatile]::new($ScriptDir+'\FakeCert.pfx', 'Pa$$w0rd')

$SMSID=[Microsoft.ConfigurationManagement.Messaging.Framework.SmsClientId]::new()
write-host "Certificate: " $SignCert.X509Certificate.FriendlyName
return $SignCert
}


function GetIPs
{

#The usual Wmi-class is not always available depending on when the script is started.
#This is what I've found available even in OOBE.

$InterFaces=[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()
[system.object[]]$IPs=@()
Foreach ($Interface in $InterFaces)
{
    #write-host ($Interface.GetIPProperties().UnicastAddresses.Address )
    $IP=($Interface.GetIPProperties().UnicastAddresses.Address)
    #write-host ($Interface.GetIPProperties().UnicastAddresses.PrefixOrigin)
    If (($Interface.GetIPProperties().UnicastAddresses.PrefixOrigin) -eq "Dhcp")
    {
	    #write-host ($Interface.GetIPProperties().UnicastAddresses.Address)
	
        $IPs+=($Interface.GetIPProperties().UnicastAddresses.Address)
    }
}
$IPs=($IPs | Where {$_ -like '*.*.*.*'})
$IPString=$IPs -join ","
Return $IPString
}


############# MAIN ##############
#@('2.5.29.37'),



$Failed=$False

If ($RunningInTS -eq $True)
{
Write-host "TSEnv is available."
$Name=$TsEnv["_SMSTSMachineName"]
$MPHost=($TSEnv["_SMSTSMP"]).Replace("http://","").Replace("https://","")

    if ($Name -eq "")
    {
        #Probably running as a prestart command.
        write-host "Could not get name from TSEnv."
        $Name=$Env:ComputerName
    }
}
else
{
Write-host "Script is NOT running inside a TS."
$Name=$Env:ComputerName
}

If ($WinPE -eq $false)
{
	Write-host "Not running in WinPE."
	try
	{
		
		$SignCert = (@(Get-ChildItem -Path "Cert:\LocalMachine\SMS" | Where-Object { $_.FriendlyName -eq "SMS Signing Certificate" }) | Sort-Object -Property NotBefore -Descending)[0]
		$SignCert= [Microsoft.ConfigurationManagement.Messaging.Framework.MessageCertificateX509File]::new('SMS', $SignCert.Thumbprint)
		$SMSID=get-wmiobject -ComputerName '.' -Namespace root\ccm -Query "Select ClientID from CCM_Client" |% ClientID
		$MPHost=(get-wmiobject -Class SMS_Authority -Namespace "root\ccm").CurrentManagementPoint
        
	}
	catch
	{
		$Failed=$True
		Write-Host "Failed finding SMS certificates."
		Write-Host "Probably not a ConfigMgr-Client."
        $NeedForReg=$True
		$SignCert=ImportFakeCert
	}
}
else
{
Write-host "Running in WinPE."
$NeedForReg=$True
$SignCert=ImportFakeCert
#$SMSID="GUID:D692E1BF-5975-4A42-AAB8-D2A62AA87CD8"
#$SignCert= [Microsoft.ConfigurationManagement.Messaging.Framework.MessageCertificateX509Volatile]::new($ScriptDir+'\FakeCert.pfx', 'Pa$$w0rd')
}

If($PSBoundParameters.ContainsKey('MP'))
{
$MPHost=$MP
}

if ($MPHost -in ($null,""))
{
    write-host "MPHost is null. Try adding it manually by using the argument -MP."
    Stop-Transcript
    break
}

If($PSBoundParameters.ContainsKey('MachineName'))
{
    $Name=$MachineName
}
Write-host "MPHost: " $MPHost
Write-host "Certificate Friendly Name: " $SignCert.X509Certificate.FriendlyName
write-host "ClientName: " $Name
write-host "SMSID: " $SMSID
write-host "Need to register to MP: " $NeedForReg
#Read-host
#$MPHost=($TSEnv["_SMSTSMP"]).Replace("http://","").Replace("https://","")

$Sender = New-Object -TypeName Microsoft.ConfigurationManagement.Messaging.Sender.Http.HttpSender

#Registers the client if needed
if ($NeedForReg -eq $True)
{
$AgentIdentity = "MyLittleAgent"
$Request= [Microsoft.ConfigurationManagement.Messaging.Messages.ConfigMgrRegistrationRequest]::new()   
$Request.AddCertificateToMessage($SignCert, [Microsoft.ConfigurationManagement.Messaging.Framework.CertificatePurposes]::Signing)
$Request.Settings.HostName = $MPHost
[void]$Request.Discover() 
$Request.AgentIdentity = $AgentIdentity
$Request.NetBiosName = $Name

$Request.Settings.Compression = [Microsoft.ConfigurationManagement.Messaging.Framework.MessageCompression]::Zlib
$Request.Settings.ReplyCompression = [Microsoft.ConfigurationManagement.Messaging.Framework.MessageCompression]::Zlib
$SMSID=$Request.RegisterClient($Sender, [TimeSpan]::FromMinutes(5))
}
write-host "SMSID is Now: " $SMSID

#Building the status message
$Message =[Microsoft.ConfigurationManagement.Messaging.Messages.ConfigMgrStatusMessage]::new()
$Message.Settings.HostName=$MPHost
$Message.Discover()
$Message.Initialize()
$Message.StatusMessage.StatusMessageType=$ClassName
								  
$Message.SmsId=$SMSID

Get-Content $ScriptDir\$TemplateName'Prop.txt' | Foreach-Object{
    $var = $_.Split('=')
    If ($var[0] -eq "*ClassName")
    {
        $ClassName=$var[1]
    }
}

write-host ""
Write-host "Properties:"
write-host ""
Get-Content $ScriptDir\$TemplateName'Prop.txt' | Foreach-Object{
   
   $var = $_.Split('=')
   if ($var[0].StartsWith("*") -eq $False)
   {

    #New-Variable -Name $var[0] -Value $var[1]
    If($PSBoundParameters.ContainsKey($var[0]))
    {
        #Write-host $PSBoundParameters[$var[0]]
        $var[1]=$PSBoundParameters[$var[0]]
    }
    #$Prop=[Microsoft.ConfigurationManagement.Messaging.Messages.StatusMessageProperty]::new(($var[0]),($var[1]))
    #$Message.StatusMessage.Properties.Properties.Add($Prop)
   
    if ($var[1].StartsWith('$ReplyTo') -eq $True)
    {
        $var[1]=$Message.MessageId.Remove(0,1).Remove(($Message.MessageId.Length-2),1)
        #$Prop=[Microsoft.ConfigurationManagement.Messaging.Messages.StatusMessageProperty]::new(($var[0]),($var[1]))
        #$Message.StatusMessage.Properties.Properties.Add($Prop)

        #write-host $Message.MessageId
    }
    if ($var[1].StartsWith('$IPs') -eq $True)
    {
      $IP= GetIPs
      $var[1]=$IP
      #$Prop=[Microsoft.ConfigurationManagement.Messaging.Messages.StatusMessageProperty]::new(($var[0]),($var[1]))
      #$Message.StatusMessage.Properties.Properties.Add($Prop)
      
    }

   $Prop=[Microsoft.ConfigurationManagement.Messaging.Messages.StatusMessageProperty]::new(($var[0]),($var[1]))
   $Message.StatusMessage.Properties.Properties.Add($Prop)
   }
   write-host ($var[0] + "=" + $var[1])
   
}
$Prop=[Microsoft.ConfigurationManagement.Messaging.Messages.StatusMessageProperty]::new("MachineName",$Name)
write-host $Prop.Name=($Prop.valueString)
$Message.StatusMessage.Properties.Properties.Add($Prop)


write-host ""
Write-host "Qualifiers:"
write-host ""
Get-Content $ScriptDir\$TemplateName'Quals.txt' | Foreach-Object{
   
   $var = $_.Split('=')
   if ($var[0].StartsWith("'") -eq $False)
   {
        If($PSBoundParameters.ContainsKey($var[0]))
        {
            $var[1]=$PSBoundParameters[$var[0]]
        }
        #New-Variable -Name $var[0] -Value $var[1]
        $Qual=[Microsoft.ConfigurationManagement.Messaging.Messages.StatusMessageQualifier]::new(($var[0]),($var[1]))
        $Message.StatusMessage.Qualifiers.Qualifiers.Add($Qual)
        write-host ($var[0] + "=" + $var[1])
   }

}

$Message.AddCertificateToMessage($SignCert, [Microsoft.ConfigurationManagement.Messaging.Framework.CertificatePurposes]::Signing)
$Message.Settings.MessageSourceType=[Microsoft.ConfigurationManagement.Messaging.Framework.MessageSourceType]::Client
$Message.Validate([Microsoft.ConfigurationManagement.Messaging.Framework.IMessageSender]$Sender)
$Message.SendMessage($Sender)

If ($ExpectReply -eq $true)
{
    write-host "";
    write-host "Expecting reply."

    #Creates a firewall rule to allow the port.
    powershell.exe -ep bypass -file $PSScriptRoot\Create-FireWallRule.ps1 -Name 'HttpListener' -Ports (8081)
    
    $Timeout=$false
    write-host "Waiting for reply...";
    
    #Need to start the httplistener in a job so we can add a timeout.
    $job=Start-Job -ScriptBlock ${function:WaitForReply} -ArgumentList ($Message.MessageId.Remove(0,1).Remove(($Message.MessageId.Length-2),1))
    $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
    Wait-Job $job -Timeout $ReplyTimeout | out-null
    $stopwatch.stop()

    if ($job.State -eq "Running")
    {
        write-host "Timeout occured."

        #Makes a webrequest so that the listener is closed.
        $Wco = New-Object Net.Webclient
        $Url="http://127.0.0.1:8081/xxGUIDxx/?url=Timeout;quit"
        $UrlNew=$Url.Replace("xxGUIDxx",$Message.MessageId.Remove(0,1).Remove(($Message.MessageId.Length-2),1))
        $Wco.downloadStringAsync($UrlNew) | out-null
        $Timeout=$True
    }

    if ($Timeout -eq $False)
    {
        write-host "Seconds before receiving reply:" $stopwatch.Elapsed.Seconds
        $ReplyData=(Receive-Job -Job ($job))

        Write-host "Data:" $ReplyData
        $DataArray=$ReplyData.Split(";")
        Write-host "Site Server Timezone:" $DataArray[0]
        Write-host "Site Server UTC Time:" $DataArray[1]
        $now=(Get-date -Format u)
        write-host "Current local UTC Time:" $now
        write-host ""
        write-host "Setting timezone to:" "$($DataArray[0].Replace("_"," "))";

        $datebefore=Get-date
        set-timezone -id "$($DataArray[0].Replace("_"," "))"
        $dateAfter=Get-date

        $Timespan=(($datebefore - $dateAfter) + ([dateTime]$(($DataArray[1]).Replace("_"," ")) - [dateTime]$now))
        Write-host "Time's of with" $Timespan
        write-host "Adjusting time to:" (set-date -adjust $timespan)
    }
    ($job | Remove-Job -Force)
}
write-host "";
Stop-Transcript
