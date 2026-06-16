$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), 8788)
$listener.Start()

function Send-Response {
  param(
    [System.Net.Sockets.TcpClient] $Client,
    [int] $StatusCode,
    [string] $StatusText,
    [string] $ContentType,
    [byte[]] $Body
  )

  $stream = $Client.GetStream()
  $header = "HTTP/1.1 $StatusCode $StatusText`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`n`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
  $stream.Write($headerBytes, 0, $headerBytes.Length)
  if ($Body.Length -gt 0) {
    $stream.Write($Body, 0, $Body.Length)
  }
  $stream.Close()
  $Client.Close()
}

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $buffer = New-Object byte[] 4096
      $read = $stream.Read($buffer, 0, $buffer.Length)
      $request = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
      $firstLine = ($request -split "`r?`n")[0]
      $parts = $firstLine -split " "
      $requestPath = if ($parts.Length -ge 2) { $parts[1] } else { "/" }
      $requestPath = [Uri]::UnescapeDataString(($requestPath -split "\?")[0].TrimStart("/"))

      if ([string]::IsNullOrWhiteSpace($requestPath)) {
        $requestPath = "index.html"
      }

      $fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $requestPath))
      if (-not $fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        Send-Response $client 403 "Forbidden" "text/plain; charset=utf-8" ([System.Text.Encoding]::UTF8.GetBytes("Forbidden"))
        continue
      }

      if (-not [System.IO.File]::Exists($fullPath)) {
        Send-Response $client 404 "Not Found" "text/plain; charset=utf-8" ([System.Text.Encoding]::UTF8.GetBytes("Not Found"))
        continue
      }

      $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
      $contentType = switch ($extension) {
        ".html" { "text/html; charset=utf-8" }
        ".js" { "application/javascript; charset=utf-8" }
        ".css" { "text/css; charset=utf-8" }
        ".csv" { "text/csv; charset=utf-8" }
        default { "application/octet-stream" }
      }

      Send-Response $client 200 "OK" $contentType ([System.IO.File]::ReadAllBytes($fullPath))
    }
    catch {
      if ($client.Connected) {
        Send-Response $client 500 "Internal Server Error" "text/plain; charset=utf-8" ([System.Text.Encoding]::UTF8.GetBytes("Internal Server Error"))
      }
    }
  }
}
finally {
  $listener.Stop()
}
