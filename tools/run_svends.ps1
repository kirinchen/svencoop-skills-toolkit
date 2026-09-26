# Headless validation: run the Sven Co-op dedicated server on a map, quit cleanly, dump console output.
# usage: powershell -ExecutionPolicy Bypass -File tools/run_svends.ps1 -Map dust2_pve -Seconds 90 [-Out svends.out]
param([string]$Map = "dust2_pve", [int]$Seconds = 90, [string]$Out = "svends.out",
      [string]$Sven = "C:\Program Files (x86)\Steam\steamapps\common\Sven Co-op",
      [string]$Steam = "C:\Program Files (x86)\Steam")
$ErrorActionPreference = 'Continue'
$env:PATH = "$Steam;" + $env:PATH          # svends needs SDL3.dll from the Steam root

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$Sven\svends.exe"
$psi.Arguments = "-console -game svencoop +sv_lan 1 +maxplayers 4 +developer 1 +map $Map"
$psi.WorkingDirectory = $Sven
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
$null = $p.Start()
$outTask = $p.StandardOutput.ReadToEndAsync()
$errTask = $p.StandardError.ReadToEndAsync()
Start-Sleep -Seconds $Seconds
try { $p.StandardInput.WriteLine("quit"); $p.StandardInput.Flush() } catch {}
if (-not $p.WaitForExit(20000)) { $p.Kill() }
$text = $outTask.Result + "`n--- stderr ---`n" + $errTask.Result
[IO.File]::WriteAllText($Out, $text)
$text -split "`n" | Where-Object { $_ -match 'Map script|compilation|spawns:|Graph|node graph|ERROR|Can.t|Couldn.t open maps' }
"exit code " + $p.ExitCode
