param(
    [string]$Arg = ''
)

try {
    $pubspecVersionName = $null

    $versionCode = [int](git rev-list --count HEAD).Trim()

    $commitHash = (git rev-parse HEAD).Trim()

    $updatedContent = foreach ($line in (Get-Content -Path 'pubspec.yaml' -Encoding UTF8)) {
        if ($line -match '^\s*version:\s*([\d\.]+)') {
            $pubspecVersionName = $matches[1]
            if ($Arg -eq 'android') {
                $pubspecVersionName += '-' + $commitHash.Substring(0, 9)
            }
            "version: $pubspecVersionName+$versionCode"
        }
        else {
            $line
        }
    }

    if ($null -eq $pubspecVersionName) {
        throw 'version not found'
    }

    $releaseTag = $env:RELEASE_TAG
    $displayVersionName = if ([string]::IsNullOrWhiteSpace($releaseTag)) {
        $pubspecVersionName
    }
    else {
        $releaseTag.Trim()
    }

    $artifactVersion = if ([string]::IsNullOrWhiteSpace($releaseTag)) {
        "$pubspecVersionName+$versionCode"
    }
    else {
        $releaseTag.Trim()
    }

    $updatedContent | Set-Content -Path 'pubspec.yaml' -Encoding UTF8

    $buildTime = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds())

    $data = @{
        'pili.name' = $displayVersionName
        'pili.code' = $versionCode
        'pili.hash' = $commitHash
        'pili.time' = $buildTime
    }

    $data | ConvertTo-Json -Compress | Out-File 'pili_release.json' -Encoding UTF8

    Add-Content -Path $env:GITHUB_ENV -Value "version=$pubspecVersionName+$versionCode"
    Add-Content -Path $env:GITHUB_ENV -Value "artifact_version=$artifactVersion"
}
catch {
    Write-Error "Prebuild Error: $($_.Exception.Message)"
    exit 1
}