# Waits for the three ConAlign window jobs, then runs the LCDR constraint variants (one process per variant).
$status = 'docs\archive\2026-10-28\conalign_paper_window\status.txt'
while (-not (Test-Path $status) -or (Get-Content $status | Measure-Object -Line).Lines -lt 3) { Start-Sleep -Seconds 60 }
$d = 'docs\archive\2026-10-28\lcdr_constraint'
foreach ($variant in 'squared', 'shared', 'lambda10') {
    $cmds = (42, 43, 44 | ForEach-Object { "venv\Scripts\python.exe $d\run.py $variant $_ >> $d\$variant.log 2>&1" }) -join ' & '
    Start-Process -FilePath cmd.exe -ArgumentList "/c $cmds & echo $variant done >> $d\status.txt" -WindowStyle Hidden -WorkingDirectory (Get-Location)
}
