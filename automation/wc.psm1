import-module "$psscriptroot/launchJson.psm1";

$slnLocation = "$psscriptroot/../sln.json";
$cmdExtension = $(
  if($psversiontable.os -match 'windows') { ".cmd" } 
  else { "" }
);

function Add-MongoSecrets($projectName) {
  $projectPath = (get-absoluteprojectpath $projectName);
  [array]$manifests = get-childitem *.yaml -path "$projectpath/k8s";

  foreach($manifest in $manifests) {
    Write-Host "Processing $($manifest.fullname)"
    $modification = $false;
    [array]$resources = ((get-content $manifest -raw) -split '---') | % { $_ | convertfrom-yaml };

    foreach($resource in $resources) {
      if($resource.kind.ToUpper() -eq 'DEPLOYMENT') {
        $targetContainer = $resource.spec.template.spec.containers | where Name -eq $projectName;

        if($targetContainer) {
          Write-Output "Adding MONGO_SERVER, MONGO_DB, MONGO_USERNAME, and MONGO_PASSWORD environment variables to $($resource.kind) $($resource.metadata.name)."
          $modification = $true;
          [System.Collections.ArrayList]$env = $targetContainer.env;

          if($env -eq $null) {
            $env = [System.Collections.ArrayList]@();
          }

          $env.Add([PSCustomObject]@{ 
            name = 'MONGO_USERNAME';
            valueFrom = @{
              secretKeyRef = @{
                name = "$projectName-mongo-secret";
                key = 'username'
              }
            }
          }) | out-null;
          $env.Add([PSCustomObject]@{
            name = 'MONGO_PASSWORD';
            valueFrom = @{
              secretKeyRef = @{
                name = "$projectName-mongo-secret";
                key = "password"
              }
            }
          }) | out-null;
          $env.Add([PSCustomObject]@{
            name = 'MONGO_SERVER';
            value = 'mongo-0.mongo'
          }) | out-null;
          $env.Add([PSCustomObject]@{
            name = 'MONGO_DB';
            value = $projectName;
          }) | out-null;

          $targetContainer.env = $env;
        }
      }
    }

    if($modification) {
      Write-Output "Saving changes to $($manifest.fullname)"
      $newContent = [string]::Join("---`n", ($resources | % { $_ | convertto-yaml }))
      $newContent | Out-File $manifest.fullname -nonewline
    }
  }
}

function Get-AbsoluteProjectPath($projectName) {
  (resolve-path "$psscriptroot/../src/$projectName").Path -replace '\\','/'
}

function Get-BrowserifyPath($projectPath) {
  "$projectpath/dist/$defaultBuildNumber.js"
}

$projectTypes = @('lib','ui','api', 'test');
function IsValidProjectType($type) {
  $projectTypes -contains $type;
}
$runnableTypes = @('ui','api', 'test');
function IsRunnableProjectType($type) {
  $runnableTypes -contains $type;
}
function Get-TsDependencies($project) {
  $deps = $project.ts_modules;

  foreach($dep in $deps) {
    if($dep.getType().Name -eq 'string') {
      $deps += Get-TsDependencies (get-wcproject $dep);
    }
  }

  $deps;
}

function Get-KubernetesResources([string][Parameter(Mandatory=$true)]$projectName, $configurationName = 'local') {
  $projectPath = get-absoluteprojectpath $projectname;
  $yamlPath = "$projectpath/k8s/$configurationName.yaml";
  
  if(test-path $yamlPath) {
    $yaml = (get-content $yamlPath -raw);
    $resources = ($yaml -split '---') | % { $_ | convertfrom-yaml }; # We split the yaml file by --- because k8s supports the ability to fit multiple resources in a single yaml separated by ---.

    [array]($resources | % { [PSCustomObject]@{ kind = $_.kind; name = $_.metadata.name }});
  }
  else {
    [array]@();
  }
}

function Restore-Npm([string]$projectName) {
  $startLocation = get-location;

  set-location "$psscriptroot/..";
  $sln = get-wcsln;

  $paths = $(if($projectName) { get-wcproject $projectName } else { $sln.projects }) |
              select-object -expandproperty name |
              foreach-object { @{ name = $_; path = (get-absoluteprojectpath $_) } } |
              foreach-object { 
                Write-Host "Restoring NPM packages for [$($_.name)]."
                set-location $_.path; 
                npm i --loglevel error; 
              }

  set-location $startLocation;
}
function Restore-TsModules([string]$projectName, [switch]$skipNpm, [switch]$verbose) {
  $sln = get-wcsln;

  $projects = $(if($projectName) { get-wcproject $projectname } else { $sln.projects });

  foreach($project in $projects) { 
    Write-Output "====Restoring TS Modules for [$($project.name)]===="

    $destination = "$(get-absoluteprojectpath $project.name)/ts_modules";
    $dependencies = get-tsdependencies $project;
    if($dependencies) {
      $thisProjectPath = get-absoluteprojectpath $project.name;

      $dependenciesAsString = [string]::Join(', ', ($dependencies | foreach-object { 
        if($_.GetType().Name -eq 'string') {
          "[$_]" 
        }
        else {
          "[$($_.From)]"
        }
      }))
      Write-Host "Pulling $dependenciesAsString into [$projectName]."

      get-childitem $destination -recurse -erroraction silentlycontinue | remove-item -force -recurse -erroraction SilentlyContinue;
      remove-item $destination -recurse -force -erroraction silentlycontinue;
      new-item -ItemType Directory $destination -erroraction SilentlyContinue | out-null;

      foreach($dependency in $dependencies) {
        if($dependency.GetType().Name -eq 'string') {
          $operation = @{
            from = "$(get-absoluteprojectpath $dependency)/src";
            pattern = "*.ts";
            recurse = $true;
            exclude = "*.d.ts";
            to = "$destination/$dependency/";
          }
        }
        else {
          $operation = @{
            from = (resolve-path "$thisProjectPath/$($dependency.from)").Path;
            pattern = $dependency.pattern;
            to = "$destination/$($dependency.to)/";
            recurse = if($dependency.recurse -eq $null) { $false } else { $dependency.recurse };
            exclude = $dependency.exclude;
          }
        }

        [array]$files = get-childitem $operation.pattern -path $operation.from -recurse:$operation.recurse -exclude $operation.exclude;
        Write-Host "Pulling $($files.Count) *.ts files from [$dependency] ($($operation.from)) into [$projectName] ($($operation.to))."

        new-item -path $operation.to -itemtype directory -erroraction silentlycontinue ;

        $files |
        select-object -expandproperty fullname |
        foreach-object {
          $source = $_ -replace '\\','/';
          $fileDestination = $source -replace $operation.from,$operation.to
          $fileDestination = $fileDestination -replace '\\','/'
          if($verbose) {
            Write-Output "$source --> $fileDestination"
          }
          if(!((get-item $source) -is [System.IO.DirectoryInfo])) {
            New-Item -itemtype file -path $fileDestination -force | out-null;
          }
          copy-item $source $fileDestination -force -recurse
        }

        if($skipNpm) {
          Write-Warning "Skipping node_modules import.";
        }
        else {
          if($dependency.GetType().Name -eq 'string') {
            $packageJsonPath = "$(get-absoluteprojectpath $dependency)/package.json";
            $packageJson = get-content $packageJsonPath | convertfrom-json;
            $nodeModules = @();
            foreach($dep in ($packageJson.dependencies.PSObject.Properties + $packageJson.devDependencies.PSObject.Properties)) {
              $nodeModules += "$($dep.Name)@$($dep.Value)";
            }

            Write-Host "Installing $($nodeModules.Length) [$dependency] node_modules in [$projectName]."

            $currentLocation = get-location;
            set-location $thisProjectPath;
            $command = "npm i $([string]::Join(' ', $nodeModules))";
            Write-Host $command;
            Invoke-Expression $command;
            set-location $currentLocation;
          }
        }
      }

      get-childitem '*.ts' -path "$thisProjectPath/ts_modules" -recurse |
      foreach-object { 
        (get-content $_ -raw) -replace '../ts_modules','../../ts_modules' | 
        out-file -filepath $_ -encoding 'UTF8' 
      }
    }
    else {
      Write-Warning "[$projectName] has no ts_modules dependencies.  Skipping."
      mkdir $destination
    }
  }
}

function Restore-WcProject($projectName) {
  $projects = $projects = if($projectName) { @(get-wcproject $projectName) } else { (get-wcsln).Projects };

  foreach($project in $projects) {
    restore-npm $project.name;
    restore-tsmodules $project.name;
  }
}

function Get-WcSln() {
  $sln = get-content $slnLocation | convertfrom-json;
  $sln.projects = [array]($sln.projects);

  $sln;
}
function Update-WcSln($sln) {
  $sln | convertto-json -depth 99 | out-file $slnLocation -force;
}
function Get-WcProject($name) {
  $sln = get-wcsln;

  $sln.projects | where-object Name -eq $name;
}
function Update-WcProject($projectName, $obj) {
  $sln = get-wcsln;
  $projectNames = $sln.projects | foreach-object { $_.name; }
  $projectIndex = [array]::indexOf($projectNames, $projectName);

  if($projectIndex -eq -1) {
    throw "Unable to find project $projectName in sln.json";
  }
  else {
    $sln.projects[$projectIndex] = $obj;
  }
  update-wcsln $sln;
}
function Connect-WcProject($projectName, $projectType, [switch]$mongo, $debugPort) {
  if(IsValidProjectType $projectType) {
    $sln = get-wcsln;

    $newProject = @{ name = $projectName; type = $projectType; ts_modules = [array]@() }

    if($projectType -eq 'ui') { 
      $newProject.ts_modules = [array]@(@{
        from = "node_modules/@depinore/wclibrary/src/";
        to = "@depinore/wclibrary";
      });
      $newProject.prodAssets = @("*.html", "node_modules", "dist", "img", "site.webmanifest", "favicon.ico");
    }
    elseif($projectType -eq 'api') {
      $newProject.mongoEnabled = [boolean]$mongo;
    }

    $sln.projects += $newProject;

    update-wcsln $sln;
  }
  else {
    Write-Error "Project type is not valid.  Must be one of: $([string]::join(', ', $projectTypes))."
  }
}
function Add-TsModule([string]$projectName, $tsModuleDefinition) {
  $proj = get-wcproject $projectName;
  if($proj) {
    $proj.ts_modules += $tsModuleDefinition;
    update-wcproject $projectName $proj;
  }
  else {
    throw "Unable to find WcProject $projectName.";
  }
}
function Disconnect-WcProject($projectName) {
  $sln = get-wcsln;
  $sln.projects = $sln.projects | where-object Name -ne $projectName;
  
  update-wcsln $sln;
}
function New-WcProject([Parameter(Mandatory=$true)]$projectName, $type = 'lib', [switch]$mongo, [int32]$debugPort = -1) {

  if($debugPort -gt -1 -and ($debugPort -lt 30000 -or $debugPort -gt 31000)) {
    throw "If provided, debugPort must be between 30000 and 31000 inclusive."
  }

  if(!(IsValidProjectType $type)) {
    Write-Error "Project type is not valid.  Must be one of: $([string]::join(', ', $projectTypes))."
  }
  else {
    if(($debugPort -lt 30000 -or $debugPort -gt 31000) -and $type -eq 'api') {
      initialize-launchjson;
      $debugPort = get-nextapidebugport;
      Write-Host "Defaulting debugPort for $projectName to $debugPort."
    }

    $slnName = (get-wcsln).name;
    $loc = get-location;
    $projectLocation = "$psscriptroot/../src/$projectName"
    new-item -itemtype Directory -path $projectLocation;
    set-location $projectLocation;

    copy-item "$psscriptroot/templates/$type/*" $projectLocation -recurse;
    connect-wcproject $projectName $type -mongo:$mongo;

    # Any sections that should have the name of the project itself, like YAML files, will be replaced here.
    get-childitem * -path $projectLocation -file -recurse |
    foreach-object {
      $content = (get-content $_.fullname -raw);
      
      if($content.Contains('_REPLACE_ME_') -or $content.Contains('_SOLUTION_NAME_') -or $content.Contains('_DEBUG_PORT_')) {
        $content.Replace('_REPLACE_ME_', $projectName).Replace('_SOLUTION_NAME_', $slnName).Replace('_DEBUG_PORT_', $debugPort) | 
          out-file $_.fullname -Encoding 'UTF8' -nonewline
      }
    }

    restore-npm $projectName;
    restore-tsmodules $projectName;

    if($type -eq 'api') {
      if($mongo) {
        add-mongosecrets $projectName;
      }

      initialize-launchjson;
      New-ApiDebugProfile $projectName $debugport;
      initialize-tasksjson;
      new-apidebugtask $projectname;
    }

    set-location $loc;
  }
}

function Clear-WcProject([string]$projectName) {
  $projects = if($projectName) { @(get-wcproject $projectName) } else { (get-wcsln).Projects };

  foreach($project in [array]($projects)) {
    $path = get-absoluteprojectpath $project.name;
    remove-item "$path/node_modules" -recurse -force -erroraction silentlycontinue;
    remove-item "$path/ts_modules" -recurse -force -erroraction silentlycontinue;
    remove-item "$path/dist" -recurse -force -erroraction silentlycontinue;
    get-childitem "*.js.*" -recurse -path "$path/src" | remove-item -recurse -force
  }
}


function Sync-DevPod([string]$projectName) {
  $project = get-wcproject $projectName;
  if($project) {
    $source = get-absoluteprojectpath $project.Name;
    $destination = if($project.Type -eq 'ui') { '/usr/share/nginx/html' } else { '/app' }
    
    $pods = kubectl get pods | % { (-split $_)[0] } | where { $_ -match "$projectName-deployment*" }
    $itemsToPush = get-childitem -path $source | select -expandproperty fullname;

    [Array]$cmds = @();

    foreach($pod in $pods) {
      foreach($item in $itemsToPush) {
        $cmds += "kubectl cp $item $($pod):$destination"
      }
    }

    $numCpus = (cat /proc/cpuinfo | grep processor | wc -l);

    if(!$verbose) {
      Write-Host "[$((get-date).ToString('T'))] Pushing files to running pods..." -NoNewLine
    }

    $cmds | invoke-parallel { 
      if($verbose) {
        Write-Output $_;
      }
      iex $_;
    } -throttlelimit $numCpus -noprogress;

    if(!$verbose) {
      Write-Host "done."
    }
  }  
  else {
    throw "Unable to find project $projectName.";
  }  
}


$defaultBuildNumber = '--buildnumber--';
function Build-WcProject([string]$projectName, [switch]$compat, [switch]$optimize, [int32]$msPauseForIO = 0, [switch]$skipNpm, $dockerfile, [switch]$skipContainer, [ScriptBlock]$preContainerActions) {
  $projects = if($projectName) { @(get-wcproject $projectName) } else { (get-wcsln).Projects };

  foreach($project in [array]($projects)) {
    if(IsValidProjectType $project.type) {
      function BasicCompile() {
        Write-Output "====Compiling TypeScript===="
        & "$projectpath/node_modules/.bin/tsc$cmdExtension" -p "$projectPath/tsconfig.json";
        
        if($lastExitCode -ne 0) {
          throw "tsc exited with a non-zero exit code.";
        }
      }
      function Containerize() {
        if(!$skipContainer) {
          if($preContainerActions) {
            Write-Output "Executing custom actions before sending files into its container."
            &$preContainerActions;
          }
          $df = if(!$dockerFile) { "$projectpath/Dockerfile" } else { $dockerFile }
          Write-Output "Packaging project into a container using $df."
          docker build $projectPath -f $df -t "$(create-projectprefix $project.name):local" --no-cache
        }
      }

      $preBuildPath = "$projectpath/automation/preBuild.ps1";
      if(test-path $preBuildPath) {
        Write-Output "Executing $preBuildPath."
        & $preBuildPath;
      }

      Write-Host "Building [$($project.name)].";
      $projectPath = get-absoluteprojectpath $project.name;

      restore-tsmodules $projectname -skipnpm:$skipnpm;

      if($project.type -ne 'ui' -and $optimize) {
        Write-Warning "The -optimize flag is only used in 'ui' projects.  Because [$($project.name)] is a '$($project.type)' project, it will be ignored."
      }

      if(test-path "$projectPath/dist*") {
        get-childitem  "$projectPath/dist*" | remove-item -recurse -force;
      }

      if($project.type -eq 'ui') {
        $compilations = @();

        if($compat) {
          $compilations += @{ tsConfig = "$projectpath/tsconfig-compat.json"; outFile = "$projectPath/dist/compat_$defaultBuildNumber.js"; name = "$($project.name)_compat"};
        }

        $compilations += @{ tsConfig = "$projectPath/tsconfig.json"; outFile = (get-browserifypath $projectPath); name = $project.name }

        foreach($compilation in $compilations) {
          Write-Host "- Running tsc for [$($compilation.name)]."
          & "$projectPath/node_modules/.bin/tsc$cmdExtension" -p $compilation.tsConfig;
          Start-Sleep -Milliseconds $msPauseForIO; # need this here because containers are delicate.
          if($lastexitcode -ne 0) {
            throw "tsc command exited with exit code $lastexitcode.";
          }

          Write-Host "- Running browserify for [$($compilation.name)] into $($compilation.outFile)";
          & "$projectPath/node_modules/.bin/browserify$cmdExtension" "$projectPath/src/index.js" --outfile $compilation.outFile $(if(!$optimize) { "--debug" });
          Start-Sleep -Milliseconds $msPauseForIO; # need this here because containers are delicate.

          if($optimize) {
            Write-Host "- Running uglify for [$($compilation.name)] on $($compilation.outFile).";
            & "$projectPath/node_modules/.bin/uglifyjs$cmdExtension" $compilation.outFile -cm -o $compilation.outFile;
          }
        }

        Containerize;
      }
      elseif($project.type -eq 'api') {
        BasicCompile;
        Write-Output "====Building Docker Image===="
        Containerize;
      }
      else {
        BasicCompile;
      }

      $postBuildPath = "$projectpath/automation/preBuild.ps1";
      if(test-path $postBuildPath) {
        Write-Output "Executing $postBuildPath."
        & $postBuildPath;
      }
    }
    else {
      Write-Warning "Project [$($project.name)] has an unrecognized type of '$($project.type)'.  Skipping build."
    }
  }
}

function Export-ProdAssets([parameter(Mandatory=$true)][string]$projectName, $buildNumber = (get-date).Ticks, [string]$environment = 'prod', [switch]$gzip) {
  $project = get-wcproject $projectName;
  if($project) {
    if($project.type -ne 'ui' -or !($project.prodassets)) {
      throw "Only projects of type 'ui' and which have prodassets defined can be exported.";
    }
    else {
      $projectLocation = get-absoluteprojectpath $project.name;
      $exportLocation = "$projectLocation/dist_prod"
      if(test-path $exportLocation) {
        remove-item $exportLocation -recurse -force;
      }
      new-item -itemtype directory $exportLocation | out-null;

      # to make sure only expected modules are included in the production build, we will take special steps with the node_modules folder.
      $includesNodeModules = ($project.prodAssets | where-object { $_ -match '.*node_modules.*'}).Count -gt 0;
      if($includesNodeModules) {
        Write-Host "node_modules will be included in the package.  Ensuring only runtime dependencies are included."
        $npmDependencies = (Get-Content "$projectLocation/package.json" -raw | convertfrom-json).dependencies;

        $currentLocation = get-location;
        set-location $exportLocation;

        $packages = $npmDependencies.PSObject.Properties |
                    foreach-object {
                      $packageName = $_.Name;
                      $packageVersion = $_.Value;

                      "$packageName@$packageVersion"
                    };
        $command = "npm i $([string]::join(' ', $packages)) --loglevel error --no-package-lock";
          
        Write-Host "Executing command: $command";
        invoke-expression $command;
        set-location $currentLocation;
      }

      Write-Host "Moving all prodassets to the exportLocation.";
      foreach($prodasset in ($project.prodassets | where-object { $_ -notmatch '.*node_modules.*' })) {
        $prodassetPath = "$projectLocation/$prodasset";
        if(!(test-path $prodAssetPath)) {
          throw "Unable to find $prodAssetPath, which is specified as a prodAsset.  (Did you forget to build your project?)"
        }
        else {
          $fqExportLocation = (resolve-path $exportLocation).path;
          Write-Host "$prodassetpath --> $fqExportLocation";
          copy-item $prodassetPath $fqExportLocation -recurse;
        }
      }

      Write-Host "Replacing any instance of '--buildNumber--' both in file contents and file names.";
      get-childitem $exportLocation -recurse | 
      foreach-object {
        if($_ -is [System.IO.FileInfo]) {
          $fileContents = get-content $_ -raw;
          if($fileContents -match $defaultBuildNumber) {
            Write-Host "Found $defaultBuildNumber in $_";
            $fileContents -replace $defaultBuildNumber,$buildNumber | out-file $_ -force;
          }
        }

        if($_ -match ".*$defaultBuildNumber.*") {
          $newName = $_ -replace $defaultBuildNumber,$buildNumber;
          Write-Host "Renaming $_ --> $newName";

          Rename-Item $_ $newName;
        }
      }

      $rootHtmlLocation = "$exportLocation/index.html";
      if(test-path $rootHtmlLocation) {
        Write-Host "Found $rootHtmlLocation.  Inserting window.build_environment = '$environment' into a <script /> tag."
        $indexHtml = (get-content $rootHtmlLocation -raw);
        $indexHtml -replace "<head>","<head>`n`t<script>`n`t`t//This was added by wc.psm1`n`t`twindow.build_environment = '$environment';`n`t</script>" | set-content $rootHtmlLocation
      }
    }

    if($gzip) {
      Write-Host "Applying gzip compression to all files.";
      get-childitem * -path $exportLocation -recurse | 
      foreach-object {
          if($_ -isNot [System.IO.DirectoryInfo]) {
              gzip --force --best -v $_.fullname;
              rename-item "$($_.fullname).gz" $_.name
          }
      }
    }
  }
  else {
    throw "Unable to find project $projectName.";
  }
}
function Create-ProjectPrefix($projectName) {
  "wc_$((get-wcsln).Name)_$($projectName)";
}
function Watch-Wcproject([parameter(Mandatory=$true)]$projectName) {
  $project = get-wcproject $projectName;

  if($project) {
    if($project.type -eq 'api' -or $project.type -eq 'ui') {
      $path = get-absoluteprojectpath $project.name;
      while($true) {
        get-childitem -recurse -path $path -exclude '*.d.ts','.*.d.ts.map','*.js' |
          select -expandproperty fullname |
          entr -d -s "pwsh -c 'import-module $psscriptroot/wc.psm1; build-wcproject $($project.name) -skipcontainer; sync-devpod $($project.name)'"
      }
    }
    else {
      throw "Only API or UI projects are watchable, as they are the only ones that run in a container.";
    }
  }
}
function Start-WcProject([parameter(Mandatory=$true)]$projectName, [switch]$skipBuild, $customBuildBlock) {
  $project = get-wcproject $projectName;

  if($project) {
    if(!(IsRunnableProjectType $project.type)) {
      throw "[$($project.name)] is of type '$($project.type)'.  Only projects of type $([string]::join(' or ', ($runnableTypes | foreach-object { "'$($_)'"}))) are runnable."
    }
    else {
      $projectPath = get-absoluteprojectpath $project.name;
      $jobPrefix = create-projectprefix $projectname;
      $projectPrefix = $jobPrefix;
      if(!$skipBuild) {
        if($customBuildBlock) {
          &$customBuildBlock;
        }
        else {
          build-wcproject $projectName
        }
      }

      $preStart = "$projectpath/automation/preStart.ps1";
      if(test-path $preStart) {
        Write-Output "Executing $preStart."
        & $preStart;
      }

      if($project.type -eq 'api' -or $project.type -eq 'ui') {
        $podPrefix = "$projectprefix-deployment";
        
        Write-Output "====K8s Stuff===="
        Write-Output "Pushing the latest $podPrefix to local k8s."
        kind load docker-image "$($projectprefix):local"

        foreach($podName in $podNames) {
          Write-Output "kubectl delete $podname"
          kubectl delete $podName -n (get-wcsln).Name;
        }

        $yamlPath = resolve-path "$projectpath/k8s/local.yaml"
        $sln = (get-wcsln).name;
        $cmd = "kubectl apply -f $yamlpath -n $sln";
        Write-Output $cmd
        iex $cmd;

        $deploymentName = "$($project.name)-deployment";
        kubectl rollout restart deployment $deploymentName -n (get-wcsln).name;
      }
      elseif($project.type -eq 'test') {
        $projectpath = (get-absoluteprojectpath $project.name) -replace '\\','/'
        $currentLocation = get-location;
        set-location $projectpath;
        npm t
        set-location $currentLocation;
      }

      $postStart = "$projectpath/automation/postStart.ps1";
      if(test-path $postStart) {
        Write-Output "Executing $postStart."
        & $postStart;
      }
    }
  }
  else {
    throw "Unknown project '$projectName'.";
  }
}
function Remove-Wcproject($name, [switch]$force) {
  $continue = $true;
  if(!$force) {
    $userInput = '';

    do {
      $userInput = Read-Host -Prompt "WARNING: This will remove [$name] from the solution and remove its entire directory from the disk.  (To only remove from solution, use 'Disconnect-Wcproject' instead.)`nContinue? [y/n]"
      $userInput = $userInput.Trim().ToUpper();
    }
    while($userInput -ne 'Y' -and $userinput -ne 'N');

    $continue = $userInput -eq 'Y';
  }

  if($continue) {
    $k8sResources = get-KubernetesResources $name;
    foreach($resource in $k8sresources) {
      kubectl delete $resource.kind $resource.name -n (get-wcsln).name;
    }
    remove-item (get-absoluteprojectpath $name) -recurse -force;
    disconnect-wcproject $name;
  }
}

Export-ModuleMember New-WcProject, Connect-WcProject, Add-TsModule, Remove-Wcproject, Watch-Wcproject, Sync-Devpod, Disconnect-WcProject, Get-WcSln, Restore-WcProject, Restore-Npm, Restore-TsModules, Build-WcProject, Get-WcProject, Export-ProdAssets, Start-WcProject, Clear-WcProject, Get-KubernetesResources, Add-MongoSecrets;