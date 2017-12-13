$msbuild = "C:\Program Files (x86)\MSBuild\14.0\Bin\MSBuild.exe"
$msDeploy = "C:\Program Files\IIS\Microsoft Web Deploy V3\msdeploy.exe"
$aspnetCompiler = "$env:windir\microsoft.net\framework64\v4.0.30319\aspnet_compiler.exe"

$mydir = (Get-Item -Path ".\" -Verbose).FullName
$outputPath = "$mydir\output"

$reverseProxyFile = "c:\testapp\web.config"
$testappUrl = "http://localhost/testapp"
$testapp1Url = "http://localhost:8080"
$testapp1Dir = "c:\testapp1"
$testapp2Url = "http://localhost:8081"
$testapp2Dir = "c:\testapp2"

# compile and build the package

Remove-Item $outputPath -Recurse -ErrorAction Ignore
&$msbuild /p:configuration=release /p:deployonBuild=true /p:DeployDefaultTarget=WebPublish /p:WebPublishMethod=FileSystem /p:publishurl="$outputPath" /verbosity:minimal
if ($LastExitCode -ne 0) { exit }


# check which instance is currently live by making a HTTP request to up.html

try 
{
    echo "`nChecking $testapp1Url for up.html"
    $webRequestResult = (New-Object System.Net.WebClient).DownloadString("$testapp1Url/up.html")
    $deployInternalUrl = $testapp2Url
    $deployInternalUrlOld = $testapp1Url
    $deployDir = $testapp2Dir
    $deployDirOld = $testapp1Dir
}
catch 
{
    $deployInternalUrl = $testapp1Url
    $deployInternalUrlOld = $testapp2Url
    $deployDir = $testapp1Dir
    $deployDirOld = $testapp2Dir
}

echo "`nDeploying to: $deployDir which is $deployInternalUrl"
echo "(Last deployed to: $deployDirOld which is $deployInternalUrlOld)`n"


# From here, deploy to $deployDir

&$msdeploy -verb:sync -source:contentPath="$outputPath" -dest:contentPath="$deployDir"

# Pre-compile our app to reduce application startup time:

echo "`nRunning the aspnet compiler in $deployDir`n"

try 
{
    &$aspnetCompiler -v /$iisPath -p $deployDir -errorstack | write-host
}
catch [System.AppDomainUnloadedException]
{
    &$aspnetCompiler -v /$iisPath -p $deployDir -errorstack | write-host
}

# Check that the newly deployed app is up and running:

try 
{
    echo "`nChecking $deployInternalUrl is responding ok`n"
    $webRequestResult = ` 
        (New-Object System.Net.WebClient).DownloadString($deployInternalUrl)
}
catch 
{
    echo "Newly deployed app failed to startup properly, cancelling switchover"
    exit
}




# Modify reverse proxy file

echo "Updating reverse proxy config file $reverseProxyFile to point towards $deployInternalUrl`n"

$content = [Io.File]::ReadAllText($reverseProxyFile) 
$updatedContent = $content -ireplace 'action type="Rewrite" url=".*"', `
    "action type=""Rewrite"" url=""$deployInternalUrl/{R:1}"""
		
Out-File -FilePath $reverseProxyFile -InputObject $updatedContent -Encoding UTF8

# Move the up file so that the next deploy works ok

echo "Moving uptime file from $deployDirOld\up.html to $deployDir\up.html"
move "$deployDirOld\up.html" "$deployDir\up.html"


# Make a request to the live URL just to make sure everything is ok:

echo "Making a request to $testappUrl to make sure everything is ok"
$webRequestResult = (New-Object System.Net.WebClient).DownloadString($testappUrl)

echo "`nDone!"
