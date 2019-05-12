Param (
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$True)]
   [String] $IPs,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$True)]
   [string] $GUID,
   [Parameter(ValueFromPipelineByPropertyName,Mandatory=$False)]
   [string] $MachineName
)
Start-Transcript -Path $Env:TEMP\webbreq2.log -Append
write-host $IPs
write-host $GUID
write-host $MachineName
try
{
    If ($MachineName)
    {
    try
    {
    $DNSIP=([System.Net.Dns]::Resolve($MachineName))
    $DNSIP1=$DNSIP.AddressList[0].IPAddressToString
    $IPs=("$IPs,$DNSIP1")
    }
    catch
    {
    write-host "Failed to resolve $MachineName"
    }
    }

    write-host "IPs:" $IPs
    $IPs1=$IPs.Split(",")
    Foreach ($IP in $IPs1)
    {
        try
        {
        Write-host "Trying IP: $IP"
        $TCPClient = New-Object Net.Sockets.TCPClient($IP,8081)
        $TCPClient.SendTimeout=500;
        $TCPClient.ReceiveTimeout=1000;
        $GetStream=$TCPClient.GetStream();

        [string]$Timzone=((Get-TimeZone).Id.ToString().Replace(' ','_'));
        Write-host $Timzone;
        $Get="GET /xxGUIDxx/?URL=xxTZxx;xxCurTimexx;quit HTTP/1.1"
        $GetNew=$Get.Replace("xxGUIDxx",$GUID).Replace("xxTZxx",$(Get-TimeZone).Id.ToString().Replace(' ','_')).Replace("xxCurTimexx",$(Get-date -Format u).Replace(' ','_'));
        write-host "GetNew" $GetNew
        $SB=New-Object Text.StringBuilder

        $SB.AppendLine("$GetNew");
        $SB.AppendLine("Host: $IP");
        #$SB.AppendLine("Connection: close");
        $SB.AppendLine("`n`n");
        $Header = [System.Text.Encoding]::UTF8.GetBytes($SB.ToString());
        write-host ($SB.ToString());
        $GetStream.Write($Header, 0, $Header.Length);
        $GetStream.Close();
        }
        catch
        {
        write-host "Error"
        $ErrorMessage = $_.Exception.Message
        write-host $ErrorMessage
        }
    }

}
catch
{
Stop-Transcript
}
Stop-Transcript
        