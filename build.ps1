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

 param (
    [Int]$minorVersions = 1,
    [switch]$dontPush = $false,
    [switch]$ignoreAPIKey = $false
 )

function isValidKubeVersion([string]$currentVersion, [string]$testVersion) {

    [Int32]$currentMinor = [convert]::ToInt32($currentVersion.Substring($currentVersion.LastIndexOf(".")+1))
    [Int32]$testMinor =  [convert]::ToInt32($testVersion.Substring($testVersion.LastIndexOf(".") + 1))

    return (($currentMinor - $minorVersions) -le $testMinor)

}

function createChocoPackage($versionInfo) {

   Write-Progress -Activity "Building package version $($versionInfo.Version)"
   Get-ChildItem .\kubernetes-node\ -File -Filter *.template -Recurse | ForEach-Object { 
      $outFile = [System.IO.Path]::Combine($_.DirectoryName, [System.IO.Path]::GetFileNameWithoutExtension($_.FullName))

      (Select-String -NotMatch "^\s*#" -Path $_.FullName  | Select-Object -ExpandProperty Line) `
                -replace "{{PackageName}}", "kubernetes-node" `
                -replace "{{PackageVersion}}", $versionInfo.Version `
                -replace "{{DownloadUrlx64}}", $versionInfo.Url `
                -replace "{{Checksumx64}}", $versionInfo.Hash > $outFile
   }

   Write-Progress -Activity "checking if $($versionInfo.Version) exists..."
   $versionExists = choco search kubernetes-node  --exact --version=$($versionInfo.Version) | Where { $_ -match "^(?<count>\d+) .*" } 
   if($matches["count"] -eq "0") {                   

      Write-Progress -Activity "packing $($versionInfo.Version)..."
      choco.exe pack .\kubernetes-node\kubernetes-node.nuspec --version=$($versionInfo.Version)
        
      Write-Progress -Activity "push $($versionInfo.Version)..."
      choco.exe push kubernetes-node.$($versionInfo.Version).nupkg --source https://push.chocolatey.org/

   }
}

function handleKubeVersion([string]$kubeVersion) {

    if( (isValidKubeVersion -currentVersion $currentVersion -testVersion $kubeVersion)  -eq $false) {
        return
    }
        
    Write-Progress -Activity "Downloading kubernetes changelog $kubeVersion"
    (Invoke-WebRequest $baseURI/CHANGELOG-$kubeVersion.md).Content -split "`n" | Where-Object { 
        $_ -match "\[kubernetes-node-windows-amd64.tar.gz\]\((?<Url>.*?/v(?<Version>\d+\.\d+\.\d+)(?<VersionFlag>-.*?)?\/.*?)\) \| ``(?<Hash>\w+)``" 
    } | ForEach-Object {

        $version = $matches["Version"]
        if(-not [string]::IsNullOrEmpty($matches["VersionFlag"])) {
           $version += $matches["VersionFlag"].Replace(".","")
        }
          
        $versionInfo = New-Object PSObject -Property @{ "Hash" = $matches["Hash"]; "Url" = $matches["Url"]; "Version" = $version }
        CreateChocoPackage -versionInfo $versionInfo

    }

}

write-progress -Activity "Checking for administrive rights..."
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 if($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -eq $false) {
     write-error "Current shell is not administrive to install chocolatey!"
     exit 1
 }

Write-Progress -Activity "Checking for chocolatey..."
if ($null -eq (Get-Command "choco.exe" -ErrorAction SilentlyContinue)) { 
    write-progress -activity "installing chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}


if( $null -eq (Invoke-Command  -FilePath "choco.exe"  -ArgumentList @("apikey", "-get", "-source", "https://push.chocolatey.org/", "-r"))) {
    if( $null -eq $env:ChocoApiKey) {
        write-error "Please set environment variable ChocoApiKey!"
        exit 1
    }

    Write-Progress -Activity "setting apikey..."
    choco apikey --key $env:ChocoApiKey --source https://push.chocolatey.org/
}
Write-Progress -Activity "Removing previous packages..."
Remove-Item *.nupkg

$latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/kubernetes/kubernetes/releases/latest" -Method Get 
$a = [regex]"(\d+\.\d+)"
$currentVersion = $a.Matches($latestRelease.name)

Write-Progress -Activity "Downloading kubernetes changelog"
$baseURI = "https://raw.githubusercontent.com/kubernetes/kubernetes/master"

(Invoke-WebRequest $baseURI/CHANGELOG.md).Content -split "`n" | Where-Object { 
    $_ -match "CHANGELOG-(?<Version>\d+\.\d+)" 
} | ForEach-Object {

    $kubeVersion = $matches["Version"]
    handleKubeVersion -kubeVersion $kubeVersion

}
