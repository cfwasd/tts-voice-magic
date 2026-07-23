[CmdletBinding()]
param(
    [string]$BaseUrl = "https://tts.wangziheng.dpdns.org",
    [string]$Text = "这是一个较长的流式语音测试句子。" * 40,
    [string]$Voice = "zh-CN-XiaoxiaoNeural"
)

$ErrorActionPreference = "Stop"
$root = $BaseUrl.TrimEnd('/')
$endpoint = "$root/v1/audio/speech"
$payloadFile = Join-Path $PSScriptRoot "stream-payload.json"
$headerFile = Join-Path $PSScriptRoot "stream-headers.txt"
$traceFile = Join-Path $PSScriptRoot "stream-trace.log"
$outputFile = Join-Path $PSScriptRoot "stream-result.mp3"

$payload = @{ input = $Text; voice = $Voice; speed = 1; pitch = "0"; style = "general" } | ConvertTo-Json -Compress
[IO.File]::WriteAllText($payloadFile, $payload, (New-Object Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $headerFile, $traceFile, $outputFile -Force -ErrorAction SilentlyContinue

Write-Host "Endpoint: $endpoint" -ForegroundColor Cyan
Write-Host "Voice: $Voice"
Write-Host "Text length: $($Text.Length)"
Write-Host ""

& curl.exe -sS -N `
    --dump-header $headerFile `
    --trace-time `
    --trace-ascii $traceFile `
    --write-out "`nTTFB=%{time_starttransfer}s`nTOTAL=%{time_total}s`n" `
    --request POST $endpoint `
    --header "Content-Type: application/json" `
    --data-binary "@$payloadFile" `
    --output $outputFile

if ($LASTEXITCODE -ne 0) { throw "curl failed with exit code $LASTEXITCODE" }

$headers = Get-Content -LiteralPath $headerFile -Raw
$size = (Get-Item -LiteralPath $outputFile).Length
$recvLines = @(Select-String -LiteralPath $traceFile -Pattern "Recv data")
$records = foreach ($item in $recvLines) {
    if ($item.Line -match '(\d{2}:\d{2}:\d{2}\.\d+) <= Recv data, (\d+) bytes') {
        [pscustomobject]@{ Time = $Matches[1]; Bytes = [int64]$Matches[2] }
    }
}

Write-Host "`nResponse headers:" -ForegroundColor Green
$headers
Write-Host "Response bytes: $size"
Write-Host "Recv data blocks: $($records.Count)"
if ($records.Count -gt 0) {
    Write-Host "First data: $($records[0].Time), $($records[0].Bytes) bytes"
    Write-Host "Last data : $($records[-1].Time), $($records[-1].Bytes) bytes"
}

if ($headers -match '(?im)^Content-Type:\s*application/json') {
    Write-Host "`nThe endpoint returned JSON instead of audio:" -ForegroundColor Red
    [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($outputFile))
    exit 1
}

if ($records.Count -gt 1) {
    Write-Host "`nMultiple response chunks observed. Check TTFB versus TOTAL above." -ForegroundColor Yellow
} else {
    Write-Host "`nOnly one response chunk observed." -ForegroundColor Yellow
}

Write-Host "`nArtifacts:" -ForegroundColor DarkGray
Write-Host $outputFile
Write-Host $headerFile
Write-Host $traceFile