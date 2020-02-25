## Powershell Central Monitor Script ## 
## Contributing authors - Roric Gibbs (RenewAire's Network Support Technician), mck74 (Internet Contributor), and 
## mjolinor (Internet Contributor) 
## 
## Within the same directory of the Central_Monitor.ps1 are two "database" files that it accesses in order to generate
## this email report/alert. monitored_computers.txt is the list of computers/servers that you would like to query the
## EventLog for while alert_events.csv is the list of Source and EventIDs you wish to be alerted regarding. Please
## note the correct Source and EventID must match. Finally the third file Application_loghist.xml is a living document
## that Central_Monitor checks with to make certain it is not reporting on the same event multiple times, if this file
## is deleted, Central Monitor will create another one using the $seed_depth (backlog) of 100 events(by default).
## 
## Please remember: Any changes/additions to the 'alert_events.csv' will not take affect until the Central Monitor 
## stops utilizing the file. You must stop the Central Monitor for any changes to the 'alert_events.csv'
## to take affect. 
param([switch]$ShowEvents = $false,[switch]$NoEmail = $false,[switch]$useinstanceid = $false) 
 
 
$log = "Application" 
$hist_file = $log + "_loghist.xml" 
$seed_depth = 100 
 
#run interval in minutes - set to zero for runonce, "C" for 0 delay continuous loop. 
$run_interval = 1 
 
$EmailFrom = "EMAILFROM@COMPANY.COM" 
$EmailTo = "EMAILTO@COMPANY.COM" 
$EmailSubject = "Server event notification."   
   
$SMTPServer = "YOUR.SMTP.SERVER" 
$SMTPAuthUsername = "USERNAME" 
$SMTPAuthPassword = "USERPASSWORD" 

#monitored_computers.txt is the .TXT file that lists the Computers you wished to be reported on 
$computers = @(gc monitored_computers.txt) 
$event_list = @{} 
Import-Csv alert_events.csv |% {$event_list[$_.source + '#' + $_.id] = 1} 
 
 
#see if we have a history file to use, if not create an empty $histlog 
if (Test-Path $hist_file){$loghist = Import-Clixml $hist_file} 
 else {$loghist = @{}} 
 
 
$timer = [System.Diagnostics.Stopwatch]::StartNew() 
 
function send_email { 
$mailmessage = New-Object System.Net.Mail.mailmessage  
$mailmessage.from = ($emailfrom)  
$mailmessage.To.add($emailto) 
$mailmessage.Subject = $emailsubject 
$mailmessage.Body = $emailbody 
$mailmessage.IsBodyHTML = $true 
$SMTPClient = New-Object Net.Mail.SMTPClient($SMTPServer, 25)   
$SMTPClient.Credentials = New-Object System.Net.NetworkCredential("$SMTPAuthUsername", "$SMTPAuthPassword")  
$SMTPClient.Send($mailmessage) 
} 
#START OF RUN PASS 
$run_pass = { 
 
$EmailBody = "Central Monitor has alerted on the following events: `n" 
 
$computers |%{ 
$timer.reset() 
$timer.start() 
 
Write-Host "Started processing $($_)" 
 
#Get the index number of the last log entry 
$index = (Get-EventLog -ComputerName $_ -LogName $log -newest 1).index 
 
#if we have a history entry calculate number of events to retrieve 
#if we don't have an event history, use the $seed_depth to do initial seeding 
if ($loghist[$_]){$n = $index - $loghist[$_]} 
 else {$n = $seed_depth} 
  
if ($n -lt 0){ 
 Write-Host "Log index changed since last run. The log may have been cleared. Re-seeding index." 
 $events_found = $true 
 $EmailBody += "`n Possible Log Reset $($_)`nEvent Index reset detected by Log Monitor`n" | ConvertTo-Html 
 $n = $seed_depth 
 } 
  
Write-Host "Processing $($n) events." 
 
#get the log entries 
 
if ($useinstanceid){ 
$log_hits = Get-EventLog -ComputerName $_ -LogName $log -Newest $n | 
? {$event_list[$_.source + "#" + $_.instanceid]} 
} 
 
else {$log_hits = Get-EventLog -ComputerName $_ -LogName $log -Newest $n | 
? {$event_list[$_.source + "#" + $_.eventid]} 
} 
 
#save the current index to $loghist for the next pass 
$loghist[$_] = $index 
 
#report number of alert events found and how long it took to do it 
if ($log_hits){ 
 $events_found = $true 
 $hits = $log_hits.count 
 $EmailBody += "<br><br><hr /> Alert Events on server $($_) `n <br><hr /><br>" 
 $log_hits |%{ 
  $emailbody += "<br>" 
  $emailbody += $_ | select MachineName,EventID,Message | ConvertTo-Html  
 $emailbody += "<br>" 
 } 
 } 
 else {$hits = 0} 
$duration = ($timer.elapsed).totalseconds 
write-host "Found $($hits) alert events in $($duration) seconds." 
"-"*60 
" " 
if ($ShowEvents){$log_hits | fl | Out-String |? {$_}} 
} 
 
#save the history file to disk for next script run  
$loghist | export-clixml $hist_file 
 
#Send email to the EMAILTO@COMPANY.COM if there were any monitored events found. 
if ($events_found -and -not $NoEmail){send_email} 
 
} 
#END OF RUN PASS 
 
Write-Host "`n$("*"*60)" 
Write-Host "Log monitor started at $(get-date)" 
Write-Host "$("*"*60)`n" 
 
#run the first pass 
$start_pass = Get-Date 
&$run_pass 
 
#if $run_interval is set, calculate how long to sleep before the next pass 
while ($run_interval -gt 0){ 
if ($run_interval -eq "C"){&$run_pass} 
 else{ 
 $last_run = (Get-Date) - $start_pass 
 $sleep_time = ([TimeSpan]::FromMinutes($run_interval) - $last_run).totalseconds 
 Write-Host "`n$("*"*10) Sleeping for $($sleep_time) seconds `n" 
  
#sleep, and then start the next pass 
 Start-Sleep -seconds $sleep_time 
 $start_pass = Get-Date  
 &$run_pass 
 } 
 } 