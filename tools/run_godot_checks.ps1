# Godot 점검 실행기 (5단계 후속 2): 여러 점검 장면을 병렬/순서대로 돌리고, 시간 초과·종료 코드·남은 프로세스를 기록한다.
# 이전 실행기(PowerShell 한 줄짜리)는 WaitForExit(시간) 이 false 여도 프로세스를 죽이지 않아, 멈춘 Godot 가 그대로 쌓였다.
# 여기서는 시간이 넘으면 taskkill /T 로 자식까지 정리하고, 끝난 뒤 이 실행기가 띄운 프로세스가 남았는지 확인한다.
#
# 예) 저장 지점 재시작 검증을 4개씩 병렬로 3번:
#   powershell -File tools/run_godot_checks.ps1 -Godot "C:\...\Godot.exe" -Parallel 4 -Rounds 3 -TimeoutSec 60
param(
	[Parameter(Mandatory = $true)][string]$Godot,
	[int]$Parallel = 1,
	[int]$Rounds = 1,
	[int]$TimeoutSec = 60,
	[string]$UserDir = "$env:APPDATA\Godot\app_userdata\BuildFarm",
	[string]$LogDir = "$env:TEMP\buildfarm_checks",
	# 점검 대신 이 장면 하나만 돌린다 (예: 일부러 깨뜨린 스크립트로 '종료 안 함' 재현)
	[string]$OnlyScene = ""
)

New-Item -ItemType Directory -Force $LogDir | Out-Null
# 저장 지점을 만드는 점검(support_ckpt)은 병렬 비교와 같은 파일을 다시 쓰므로 먼저 따로 한 번 돌린다
if ($OnlyScene -eq "") {
	$g = Start-Process -FilePath $Godot -ArgumentList @("--headless", "--path", ".", "res://scenes/tests/support_ckpt.tscn") -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $LogDir "support_gen.out") -RedirectStandardError (Join-Path $LogDir "support_gen.err")
	$null = $g.Handle
	if (-not $g.WaitForExit($TimeoutSec * 1000)) { taskkill /PID $g.Id /T /F | Out-Null; "support_ckpt 생성 시간 초과" }
}
$jobs = @()
foreach ($f in (Get-ChildItem "$UserDir\ckpt_*.json")) {
	# 주의: PowerShell 에서는 쉼표가 + 보다 먼저 묶이므로 이름을 괄호로 감싼다
	$jobs += ,@(("restart_" + $f.BaseName), @("--headless", "--path", ".", "res://scenes/tests/restart_check.tscn", "--", "--file=user://$($f.Name)"))
}
$jobs += ,@("support_verify", @("--headless", "--path", ".", "res://scenes/tests/support_ckpt.tscn", "--", "--verify"))  # 읽기만 함
if ($OnlyScene -ne "") {
	$jobs = @(,@("only", @("--headless", "--path", ".", $OnlyScene)))
}

$results = @()
$started = @()
for ($round = 1; $round -le $Rounds; $round++) {
	$next = 0
	$running = @()
	while ($next -lt $jobs.Count -or $running.Count -gt 0) {
		while ($running.Count -lt $Parallel -and $next -lt $jobs.Count) {
			$j = $jobs[$next]
			$next++
			# 출력 파일은 실행마다 다르게 (같은 파일을 여러 프로세스가 동시에 쓰지 않게)
			$out = Join-Path $LogDir ("{0}_r{1}_{2}.out" -f $j[0], $round, [guid]::NewGuid().ToString("N").Substring(0, 6))
			$p = Start-Process -FilePath $Godot -ArgumentList $j[1] -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out + ".err")
			$null = $p.Handle  # 종료 코드를 읽으려면 핸들을 잡아 둔다
			$started += $p.Id
			$running += ,@($p, $j[0], $out, [Diagnostics.Stopwatch]::StartNew())
		}
		Start-Sleep -Milliseconds 200
		$still = @()
		foreach ($r in $running) {
			$p = $r[0]
			if ($p.HasExited) {
				$results += [pscustomobject]@{ Round = $round; Name = $r[1]; Exit = $p.ExitCode; Seconds = [math]::Round($r[3].Elapsed.TotalSeconds, 1); TimedOut = $false; Line = ((Get-Content $r[2] -Encoding UTF8 | Select-String "RESTART|SUPPORT") -join " ") }
			} elseif ($r[3].Elapsed.TotalSeconds -gt $TimeoutSec) {
				taskkill /PID $p.Id /T /F | Out-Null
				$results += [pscustomobject]@{ Round = $round; Name = $r[1]; Exit = "killed"; Seconds = [math]::Round($r[3].Elapsed.TotalSeconds, 1); TimedOut = $true; Line = ((Get-Content ($r[2] + ".err") -Encoding UTF8 -ErrorAction SilentlyContinue | Select-String "Parse Error|SCRIPT ERROR" | Select-Object -First 1) -join " ") }
			} else {
				$still += ,$r
			}
		}
		$running = $still
	}
}
Start-Sleep -Seconds 1
$left = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $started -contains $_.Id })  # 이 실행기가 띄운 것만 (편집기 등은 제외)
$results | Where-Object TimedOut | ForEach-Object { "시간 초과: {0} (라운드 {1}) {2}" -f $_.Name, $_.Round, $_.Line }
$results | Format-Table Round, Name, Exit, Seconds, TimedOut -AutoSize | Out-String -Width 200
"모든 실행: {0} · 시간 초과: {1} · 0이 아닌 종료 코드: {2} · 남은 프로세스: {3}" -f $results.Count, @($results | Where-Object TimedOut).Count, @($results | Where-Object { $_.Exit -ne 0 -and $_.Exit -ne "killed" }).Count, $left.Count
"결과 줄이 같음(same=true)이 아닌 것: {0}" -f @($results | Where-Object { $_.Name -like "restart_*" -and $_.Line -notlike "*same=true*" }).Count
