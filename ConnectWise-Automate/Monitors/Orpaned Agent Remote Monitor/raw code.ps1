$file = "C:\Program Files (x86)\Huntress\HuntressAgent.log"
if (-not(Test-Path -Path $file -PathType Leaf)) {
    $file = "C:\Program Files\Huntress\HuntressAgent.log"
    Get-Content $file -Tail 20 | ForEach-Object { if ($_ -like "*bad status code: 401*" -or $_ -like "*bad status code:400*") {Echo "ORPHANED"}}
 } else {
 Get-Content $file -Tail 20 | ForEach-Object { if ($_ -like "*bad status code: 401*" -or $_ -like "*bad status code:400*") {Echo "ORPHANED"}}
 }
