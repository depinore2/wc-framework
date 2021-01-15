$launchJsonPath = "$psscriptroot/../.vscode/launch.json";
$taskJsonPath = "$psscriptroot/../.vscode/tasks.json";

function Get-ConfigJson($fileName) {
    if(test-path $fileName) {
        gc $fileName | convertfrom-json -depth 99;
    }
    else {
        throw "Unable to find $fileName."
    }
}
function Get-LaunchJson() {
    get-configjson $launchJsonPath;
}
function Get-TasksJson() {
    get-configjson $taskJsonPath;
}

function Initialize-LaunchJson() {
    if(!(test-path $launchJsonPath)) {
@"
{
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [

    ]
}
"@ | Out-File $launchJsonPath -NoNewLine;
    }
    else {
        Write-Warning "$launchJsonPath already exists.  Skipping."
    }
}
function Initialize-TasksJson() {
    if(!(test-path $taskJsonPath)) {
@"
{
  // See https://go.microsoft.com/fwlink/?LinkId=733558
  // for the documentation about the tasks.json format
  "version": "2.0.0",
  "tasks": [

  ]
}
"@ | Out-File $taskJsonPath -NoNewLine;
    }
    else {
        Write-Warning "$taskJsonPath already exists.  Skipping."
    }
}
function New-ApiDebugProfile([Parameter(Mandatory=$true)][string]$apiName, [Parameter(Mandatory=$true)][int32]$debugPort, $profileName = "Debug $apiName") {
    $launchJson = get-launchjson;
    $taskName = "start-wcproject $apiName";
    $debugProfile = @{
            address = "172.17.0.1";
            localRoot = "`${workspaceFolder}/src/$apiName/src";
            name = $profileName;
            port = $debugPort;
            remoteRoot = "/app/src";
            request = "attach";
            skipFiles = [array]@('<node_internals>/**');
            preLaunchTask = $taskName;
            type = 'node';
    };
    ([array]$launchJson.configurations) += $debugProfile;
    Write-Host "Adding profile '$profileName' to $launchJsonPath"
    $launchjson | convertto-json -depth 99 | out-file $launchJsonPath;

    initialize-tasksJson;
    new-apidebugtask $apiName $taskName;
}
function New-ApiDebugTask([Parameter(Mandatory=$true)][string]$apiName, $taskName = "start-wcproject $apiName") {
    $tasksJson = get-tasksJson;
    $task = @{
        label = $taskName;
        type = "shell";
        command = "pwsh -C 'import-module ./automation/wc; start-wcproject $apiName; start-sleep -seconds 5'"
    }
    ([array]$tasksJson.tasks) += $task;
    Write-Host "Adding task '$taskName' to $taskJsonPath";
    $tasksJson | convertto-json -depth 99 | out-file $taskJsonPath;
}
function Get-NextApiDebugPort() {
    $minimum = 30000;
    [array]$configurations = (get-launchJson).configurations;
    $highestOccupiedPort = ($configurations | select -expandproperty Port -erroraction silentlycontinue | measure-object -maximum).Maximum;

    if($highestOccupiedPort -lt $minimum) {
        $minimum;
    }
    else {
        $highestOccupiedPort + 1;
    }
}