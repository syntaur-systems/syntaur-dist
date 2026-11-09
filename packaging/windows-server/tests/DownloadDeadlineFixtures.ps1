# Native loopback regression fixture. Never execute the installer entrypoint.
param([Parameter(Mandatory=$true)][string]$InstallerPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($InstallerPath,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'Installer parse errors'}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Install-PinnedReleaseAsset'},$true)
if($null -eq $fn){throw 'Actual download helper missing'}
. ([scriptblock]::Create($fn.Extent.Text))
# The proposed worker fixture incorrectly dot-sourced the whole installer under
# a nonexistent library flag, and serialized HttpListener through Start-Job.
# Use only the AST-extracted helper and one owned C# loopback thread instead.
Add-Type -TypeDefinition @'
using System;using System.IO;using System.Net;using System.Net.Sockets;using System.Text;using System.Threading;
public sealed class DownloadFixtureServer : IDisposable {
 readonly TcpListener listener;readonly Thread thread;readonly string mode;volatile bool stopping;
 public readonly string Url;public int Requests;public string Failure="";
 public static readonly byte[] Payload=Encoding.UTF8.GetBytes("verified payload");
 public DownloadFixtureServer(string m) {
  mode=m;listener=new TcpListener(IPAddress.Loopback,0);listener.Start();
  Url="http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port+"/asset";
  thread=new Thread(Run);thread.IsBackground=true;thread.Start();
 }
 void Write(NetworkStream s,string v){byte[] b=Encoding.ASCII.GetBytes(v);s.Write(b,0,b.Length);s.Flush();}
 void Run(){try {
  int count=mode=="redirect"?2:mode=="redirectloop"?6:1;
  for(int i=0;i<count&&!stopping;i++)using(TcpClient c=listener.AcceptTcpClient()){
   Requests++;using(NetworkStream s=c.GetStream()){
    s.ReadTimeout=2000;int matched=0;byte[] end=Encoding.ASCII.GetBytes("\r\n\r\n");
    while(matched<4){int b=s.ReadByte();if(b<0)throw new IOException("closed request");matched=b==end[matched]?matched+1:(b==13?1:0);}
    if(mode=="headerstall"){Thread.Sleep(900);continue;}
    if(mode=="redirectloop"||(mode=="redirect"&&i==0)){Write(s,"HTTP/1.1 302 Found\r\nLocation: /asset\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");continue;}
    if(mode=="error"){Write(s,"HTTP/1.1 500 Failure\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");continue;}
    if(mode=="oversize"){Write(s,"HTTP/1.1 200 OK\r\nContent-Length: 1073741825\r\nConnection: close\r\n\r\n");continue;}
    Write(s,"HTTP/1.1 200 OK\r\nContent-Length: "+Payload.Length+"\r\nConnection: close\r\n\r\n");
    if(mode=="bodystall"){Thread.Sleep(900);continue;}
    if(mode=="trickle"){for(int j=0;j<Payload.Length;j++){Thread.Sleep(120);s.Write(Payload,j,1);s.Flush();}}
    else{s.Write(Payload,0,Payload.Length);s.Flush();}
   }
  }
 }catch(IOException){if(!stopping&&mode!="trickle")Failure="IOException";}
 catch(SocketException){if(!stopping)Failure="SocketException";}
 catch(Exception e){Failure=e.GetType().Name;}}
 public void Dispose(){stopping=true;listener.Stop();if(!thread.Join(2500))throw new Exception("Fixture thread did not retire");}
}
'@
$root=Join-Path ([IO.Path]::GetTempPath()) ('Syntaur-download-fixture-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($root)
$allowed=@{}
function Test-SafeInstallEntry {param([string]$LiteralPath,[bool]$Container) return (-not $Container -and $allowed.ContainsKey($LiteralPath))}
$hash=[Security.Cryptography.SHA256]::Create()
try{$expected=[BitConverter]::ToString($hash.ComputeHash([DownloadFixtureServer]::Payload)).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
$results=@()
function Case([string]$Name,[string]$Mode,[string]$Outcome,[bool]$Prior,[int]$Requests,[int]$Budget=3000) {
 $server=$null
 try {
 $server=New-Object DownloadFixtureServer $Mode;$p=Join-Path $root ($Name+'.bin');$allowed[$p]=$true
 $before=[Text.Encoding]::UTF8.GetBytes('preserved original')
 if($Prior){[IO.File]::WriteAllBytes($p,$before)}
 $caught=$null;$w=[Diagnostics.Stopwatch]::StartNew();$sha=if($Outcome -ceq 'hash'){'f'*64}else{$expected}
 try {Install-PinnedReleaseAsset -Url $server.Url -LiteralPath $p -ExpectedSha256 $sha -Label 'fixture' -TimeoutMs $Budget}catch{$caught=$_.Exception}
 $elapsed=$w.ElapsedMilliseconds
  if($Outcome -ceq 'success') {
   if($null -ne $caught){throw ('Unexpected download failure '+$caught.GetType().Name)}
   if([Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) -cne [Convert]::ToBase64String([DownloadFixtureServer]::Payload)){throw 'Wrong accepted payload'}
  }else{
   if($null -eq $caught){throw 'Expected refusal missing'}
   if($Outcome -ceq 'timeout') {
    $e=$caught;$timed=$false
    while($null -ne $e){if(($e -is [Net.WebException] -and $e.Status -eq [Net.WebExceptionStatus]::Timeout) -or $e.Message -like '*exceeded enclosing deadline*'){$timed=$true};$e=$e.InnerException}
    if(-not $timed -or $elapsed -lt 150 -or $elapsed -gt 750){throw 'No bounded timeout evidence'}
   }elseif($Outcome -ceq 'hash' -and $caught.Message -cne 'fixture did not match the hash pinned into this signed installer'){throw 'Wrong hash refusal'}
   elseif($Outcome -ceq 'http' -and $caught.Message -notlike '*HTTP status code 500*'){throw 'Wrong HTTP refusal'}
   elseif($Outcome -ceq 'redirect' -and $caught.Message -notlike '*too many redirects*'){throw 'Wrong redirect refusal'}
   elseif($Outcome -ceq 'size' -and $caught.Message -notlike '*size bound*'){throw 'Wrong size refusal'}
   if($Prior){if([Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) -cne [Convert]::ToBase64String($before)){throw 'Prior destination changed'}}
   elseif(Test-Path -LiteralPath $p){throw 'Failed download published destination'}
  }
  if(@(Get-ChildItem -LiteralPath $root -Filter '*.part.*' -Force).Count -or @(Get-ChildItem -LiteralPath $root -Filter '*.backup.*' -Force).Count){throw 'Partial or backup leaked'}
 }finally{if($null -ne $server){$server.Dispose()}}
 if($server.Requests -ne $Requests -or $server.Failure){throw 'Unexpected owned server outcome'}
 $script:results+=,[ordered]@{name=$Name;passed=$true;requests=$server.Requests;transfer_ms=$elapsed}
}
try {
 Case 'normal' 'normal' 'success' $false 1
 Case 'replace' 'normal' 'success' $true 1
 Case 'wronghash' 'normal' 'hash' $true 1
 Case 'headerstall' 'headerstall' 'timeout' $true 1 350
 Case 'bodystall' 'bodystall' 'timeout' $false 1 350
 Case 'trickle' 'trickle' 'timeout' $true 1 350
 Case 'httperror' 'error' 'http' $true 1
 Case 'redirect' 'redirect' 'success' $false 2
 Case 'redirectloop' 'redirectloop' 'redirect' $true 6
 Case 'oversize' 'oversize' 'size' $true 1
}finally{[IO.Directory]::Delete($root,$true)}
[ordered]@{cases_passed=$results.Count;cases_total=10;results=$results;source_sha256=(Get-FileHash -LiteralPath $InstallerPath).Hash;loopback_only=$true;no_installer_entrypoint_or_product_or_MSI_or_external_calls=$true;fixture_removed=(-not(Test-Path -LiteralPath $root))}|ConvertTo-Json -Depth 5 -Compress
