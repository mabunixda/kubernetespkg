#{{PackageName}} - Package Name (should be same as nuspec file and folder) |/p
#{{PackageVersion}} - The updated version | /v
#{{DownloadUrl}} - The url for the native file | /u
#{{PackageFilePath}} - Downloaded file if including it in package | /pp
#{{PackageGuid}} - This will be used later | /pg
#{{DownloadUrlx64}} - The 64-bit url for the native file | /u64
#{{Checksum}} - The checksum for the url | /c
#{{Checksumx64}} - The checksum for the 64-bit url | /c64
#{{ChecksumType}} - The checksum type for the url | /ct
#{{ChecksumTypex64}} - The checksum type for the 64-bit url | /ct64

Write-Progress -Activity "Downloading kubernetes changelog"

(Invoke-WebRequest https://raw.githubusercontent.com/kubernetes/kubernetes/master/CHANGELOG.md).Content -split "`n" | Where-Object { 
    $_ -match "\[kubernetes-node-windows-amd64.tar.gz\]\((?<Url>.*?/v(?<Version>\d+\.\d+\.\d+).*?)\) \| ``(?<Hash>\w+)``" 
} | ForEach-Object {
    $versionInfo = New-Object PSObject -Property @{ "Hash" = $matches["Hash"]; "Url" = $matches["Url"]; "Version" = $matches["Version"] }
    
    Write-Progress -Activity "Building package version $($versionInfo.Version)"
    Get-ChildItem .\kubernetes-node\ -File -Filter *.template -Recurse | ForEach-Object { 
        $outFile = [System.IO.Path]::Combine($_.DirectoryName, [System.IO.Path]::GetFileNameWithoutExtension($_.FullName))

        (Select-String -NotMatch "^\s*#" -Path $_.FullName  | Select-Object -ExpandProperty Line) `
            -replace "{{PackageName}}", "kubernetes-node" `
            -replace "{{PackageVersion}}", $versionInfo.Version `
            -replace "{{DownloadUrlx64}}", $versionInfo.Url `
            -replace "{{Checksumx64}}", $versionInfo.Hash > $outFile
    }

    choco.exe pack .\kubernetes-node\kubernetes-node.nuspec --version=$($versionInfo.Version)
}
