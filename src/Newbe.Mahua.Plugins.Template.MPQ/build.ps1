﻿Framework "4.6"
properties {
    $rootNow = Resolve-Path .
    $nugetexe = "$rootNow\buildTools\NuGet.exe"
    $configuration = "Debug"
    $releaseBase = "$rootNow\bin"
    $pluginName = (Get-ChildItem *.csproj).Name.Replace(".csproj", "")
    $mahuaDownloadTempDir = "$($env:TEMP)\Newbe\Newbe.Mahua"
	$assetDirName = "YUELUO"
}

$pkgNames = @{
    "platform"  = @(
        "Newbe.Mahua.CQP",
        "Newbe.Mahua.Amanda",
        "Newbe.Mahua.MPQ"
    )
    "framework" = @(
        "Newbe.Mahua",
        "Newbe.Mahua.PluginLoader"
    )
    "ext"       = @(
        "Newbe.Mahua.Administration",
        "Newbe.Mahua.CQP.ApiExtensions"
    )
}

$pkg = [xml](Get-Content .\packages.config)

$InstalledPlatforms = $pkg.packages.package | Where-Object { $pkgNames.platform.Contains($_.id) }
$installedExts = $pkg.packages.package | Where-Object { $pkgNames.ext.Contains($_.id) }
$installedFramework = $pkg.packages.package | Where-Object { $pkgNames.framework.Contains($_.id) }
$installedAll = $pkg.packages.package | Where-Object { $_.id.StartsWith("Newbe.Mahua") }

function Get-MahuaPackage {
    param (
        [string]$id
    )
    $re = ($installedAll | Where-Object { $_.id -eq $id})
    $re
    return $re[0]
}
function Get-Download-Package-ToolsDir {
    param (
        $package
    )
    return "$mahuaDownloadTempDir\$($package.id).$($package.version)\tools"
}

function Copy-FrameworkItems ($dest) {
    Exec {
        $installedFramework | ForEach-Object {
            Write-Output "copy start : $($_.id).$($_.version)"
            $framework = Get-MahuaPackage -id $_.id
            $toolBase = Get-Download-Package-ToolsDir -package $framework
            Copy-Item -Path  "$toolBase\NewbeLibs\Framework\*" -Destination $dest
            Write-Output "copy end : $($_.id).$($_.version)"
        }
    }
}

function Copy-FrameworkExtensionItems ($dest) {
    Exec {
        $installedExts | ForEach-Object {
            Write-Output "copy start : $($_.id).$($_.version)"
            $ext = Get-MahuaPackage -id $_.id
            $toolBase = Get-Download-Package-ToolsDir -package $ext
            Copy-Item -Path  "$toolBase\NewbeLibs\Framework\Extensions\*" -Destination $dest -Recurse
            Write-Output "copy end : $($_.id).$($_.version)"
        }
    }
}

Task Default -depends Pack

Task Clean -Description "清理" {
    $InstalledPlatforms | ForEach-Object {
        Exec {
            $platformName = $_.id.Split('.')[2]
            Remove-Item "$releaseBase\$platformName" -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Task Init -depends Clean -Description "初始化参数" {
    $InstalledPlatforms | ForEach-Object {
        Exec {
            Write-Output "platform installed : $($_.id).$($_.version)"
        }
    }
    $installedExts | ForEach-Object {
        Exec {
            Write-Output "extensions installed : $($_.id).$($_.version)"
        }
    }
}

Task DonwloadPackages -depends Init -Description "下载 nuget 包到临时目录" {
    $installedAll | ForEach-Object {
        $toolBase = Get-Download-Package-ToolsDir -package $_
        if (-not (Test-Path $toolBase)) {
            Write-Output "cmd : nuget install $($_.id) -version $($_.version) -OutputDirectory $mahuaDownloadTempDir -Verbosity quiet"
            cmd /c """$nugetexe"" install $($_.id) -version $($_.version) -OutputDirectory $mahuaDownloadTempDir -Verbosity quiet"
        }
    }
}

Task Nuget -depends Init -Description "nuget restore" {
    Exec {
        cmd /c """$nugetexe"" restore  -PackagesDirectory ""$rootNow\..\packages"""
    }
}

Task Build -depends Nuget -Description "编译" {
    Exec {
        msbuild /p:Configuration=$configuration
    }
}

# 生成CQP的JSON文件
function WriteCqpJsonFile ($targetFilePath) {
    # 加载所有的DLL
    Get-ChildItem  "$releaseBase\$configuration\*" *.dll | ForEach-Object {
        [void][reflection.assembly]::LoadFile($_)
    }

    # 创建实例
    $pluginInfo = New-Object "$pluginName.PluginInfo"

    $installCqpVersion = Get-MahuaPackage -id "Newbe.Mahua.CQP"
    $toolBase = Get-Download-Package-ToolsDir -package $installCqpVersion
    # 读取文件
    $jsonFile = "$toolBase\NewbeLibs\Platform\Content\Newbe.Mahua.CQP.json"
    $jsonText = Get-Content $jsonFile -Encoding "utf8"
    $json = $jsonText | ConvertFrom-Json

    # 内容赋值
    $json.name = $pluginInfo.Name
    $json.version = $pluginInfo.Version
    $json.author = $pluginInfo.Author
    $json.description = $pluginInfo.Description
    $versionNos = ""
    # 版本号每个部分*10，因此版本号，每个版本不能超过10
    $pluginInfo.version.Split(".") | ForEach-Object {
        $v = [string](10 * [int]$_)
        $versionNos += $v
    }
    $json.version_id = [int] $versionNos

    # 写入文件
    $encoding = [System.Text.Encoding]::GetEncoding("gb2312")
    [System.IO.File]::WriteAllText("$targetFilePath", ($json | ConvertTo-Json), $encoding)
}

Task PackCQP -depends DonwloadPackages, Build -Description "CQP打包" {
    $InstalledPlatforms | Where-Object {$_.id -eq "Newbe.Mahua.CQP"} | ForEach-Object {
        Exec {
            $toolBase = Get-Download-Package-ToolsDir -package $_
            New-Item -ItemType Directory "$releaseBase\CQP"
            New-Item -ItemType Directory "$releaseBase\CQP\$pluginName"
            New-Item -ItemType Directory "$releaseBase\CQP\app"
            Copy-FrameworkItems -dest "$releaseBase\CQP\"
            Copy-Item -Path  "$toolBase\NewbeLibs\Platform\CLR\*" -Destination "$releaseBase\CQP" -Recurse
            Copy-FrameworkExtensionItems -dest "$releaseBase\CQP\$pluginName"
            Copy-Item -Path "$releaseBase\$configuration\*", "$toolBase\NewbeLibs\Platform\CLR\*"   -Destination "$releaseBase\CQP\$pluginName" -Recurse
            Copy-Item -Path "$toolBase\NewbeLibs\Platform\Native\Newbe.Mahua.CQP.Native.dll" -Destination  "$releaseBase\CQP\app\$pluginName.dll"
            WriteCqpJsonFile -targetFilePath "$releaseBase\CQP\app\$pluginName.json"

            Copy-Item "$releaseBase\CQP\$pluginName" "$releaseBase\CQP\$assetDirName\$pluginName" -Recurse
            Get-ChildItem "$releaseBase\CQP\$assetDirName\$pluginName" | Get-FileHash | Out-File "$releaseBase\hash.txt"
            Copy-Item "$releaseBase\hash.txt" "$releaseBase\CQP\$assetDirName\$pluginName\hash.txt"
            Remove-Item "$releaseBase\hash.txt"
            Remove-Item "$releaseBase\CQP\$pluginName" -Recurse
        }
    }
}

Task PackAmanda -depends DonwloadPackages, Build -Description "Amanda打包" {
    $InstalledPlatforms | Where-Object {$_.id -eq "Newbe.Mahua.Amanda"}  | ForEach-Object {
        Exec {
            $toolBase = Get-Download-Package-ToolsDir -package $_
            New-Item -ItemType Directory "$releaseBase\Amanda"
            New-Item -ItemType Directory "$releaseBase\Amanda\$pluginName"
            New-Item -ItemType Directory "$releaseBase\Amanda\plugin"
            Copy-FrameworkItems -dest "$releaseBase\Amanda\"
            Copy-Item -Path  "$toolBase\NewbeLibs\Platform\CLR\*" -Destination "$releaseBase\Amanda" -Recurse
            Copy-FrameworkExtensionItems -dest "$releaseBase\Amanda\$pluginName"
            Copy-Item -Path "$releaseBase\$configuration\*", "$toolBase\NewbeLibs\Platform\CLR\*"   -Destination "$releaseBase\Amanda\$pluginName" -Recurse
            Copy-Item -Path "$toolBase\NewbeLibs\Platform\Native\Newbe.Mahua.Amanda.Native.dll" -Destination  "$releaseBase\Amanda\plugin\$pluginName.plugin.dll"

            Copy-Item "$releaseBase\Amanda\$pluginName" "$releaseBase\Amanda\$assetDirName\$pluginName" -Recurse
            Get-ChildItem "$releaseBase\Amanda\$assetDirName\$pluginName" | Get-FileHash | Out-File "$releaseBase\hash.txt"
            Copy-Item "$releaseBase\hash.txt" "$releaseBase\Amanda\$assetDirName\$pluginName\hash.txt"
            Remove-Item "$releaseBase\hash.txt"
            Remove-Item "$releaseBase\Amanda\$pluginName" -Recurse
        }
    }
}

Task PackMPQ -depends DonwloadPackages, Build -Description "MPQ打包" {
    $InstalledPlatforms | Where-Object {$_.id -eq "Newbe.Mahua.MPQ"}| ForEach-Object {
        Exec {
            $toolBase = Get-Download-Package-ToolsDir -package $_
            New-Item -ItemType Directory "$releaseBase\MPQ"
            New-Item -ItemType Directory "$releaseBase\MPQ\$pluginName"
            New-Item -ItemType Directory "$releaseBase\MPQ\Plugin"
            Copy-FrameworkItems -dest "$releaseBase\MPQ\"
            Copy-Item -Path  "$toolBase\NewbeLibs\Platform\CLR\*" -Destination "$releaseBase\MPQ" -Recurse
            Copy-FrameworkExtensionItems -dest "$releaseBase\MPQ\$pluginName"
            Copy-Item -Path "$releaseBase\$configuration\*", "$toolBase\NewbeLibs\Platform\CLR\*"   -Destination "$releaseBase\MPQ\$pluginName" -Recurse
            Copy-Item -Path "$toolBase\NewbeLibs\Platform\Native\Newbe.Mahua.MPQ.Native.dll" -Destination  "$releaseBase\MPQ\Plugin\$pluginName.xx.dll"

            Copy-Item "$releaseBase\MPQ\$pluginName" "$releaseBase\MPQ\$assetDirName\$pluginName" -Recurse
            Get-ChildItem "$releaseBase\MPQ\$assetDirName\$pluginName" | Get-FileHash | Out-File "$releaseBase\hash.txt"
            Copy-Item "$releaseBase\hash.txt" "$releaseBase\MPQ\$assetDirName\$pluginName\hash.txt"
            Remove-Item "$releaseBase\hash.txt"
            Remove-Item "$releaseBase\MPQ\$pluginName" -Recurse
        }
    }
}

Task Pack -depends PackCQP, PackAmanda, PackMPQ -Description "打包" {
    Write-Output "构建完毕，当前时间为 $(Get-Date)"
}

