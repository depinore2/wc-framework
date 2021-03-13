  import-module "$psscriptroot/launchJson.psm1";

  $slnLocation = "$psscriptroot/../sln.json";
  $cmdExtension = $(
    if($psversiontable.os -match 'windows') { ".cmd" } 
    else { "" }
  );

  function Add-MongoSecrets($projectName) {
    <#
      .SYNOPSIS
        Adds configuration to a YAML to use mongoDB secrets.

      .DESCRIPTION
        Goes through an API project's YAML file and ensures that the deployment object has environment variable references to MONGO_SERVER, MONGO_DB, MONGO_USERNAME, and MONGO_PASSWORD.
        These environment variables will give your API's code the ability to connect to mongoDB.  The mongo_username and mongo_password variables are created in your API project's automation/addMongoCreds.ps1 script.

      .PARAMETER projectName
        The name of the API project to configure with mongoDB environment variable integration.

      .EXAMPLE
          add-mongosecrets my-api-here
      #>
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
    <#
    .SYNOPSIS
      Identifies which ts_modules dependencies a project has.
    #>
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
    <#
      .SYNOPSIS
        Restores all npm packages for a project.  If no projectName is provided, it will restore the entire solution's NPM packages.
    #>
    $startLocation = get-location;

    set-location "$psscriptroot/..";
    $sln = get-wcsln;

    $paths = $(if($projectName) { get-wcproject $projectName } else { $sln.projects }) |
                select-object -expandproperty name |
                foreach-object { @{ name = $_; path = (get-absoluteprojectpath $_) } } |
                foreach-object { 
                  Write-Host "Restoring NPM packages for [$($_.name)]."
                  set-location $_.path; 
                  npm i; 
                }

    set-location $startLocation;
  }
  function Get-InstalledNpmPackages([string][Parameter(Mandatory=$true)]$projectName) {
    <#
      .DESCRIPTION
        Determines which NPM packages are already on disk for a given project.
    #>
    $startLocation = get-location;
    cd (get-absoluteprojectpath $projectName);

    $packages = ((npm ls --silent) + (npm ls -dev --silent)) | where { $_ -notmatch 'UNMET' };
    $output = $packages | 
      % { -split $_ } |
      where { $_ -match '@' }
    
    cd $startLocation;
    $output | sort-object | get-unique;
  }
  function Get-MissingTsModuleNpmPackages([string]$thisProjectName, [string[]]$tsModuleNames) {
    $nodeModules = @();
    $installedNpmPackages = get-installedNpmPackages $thisProjectName;

    foreach($dependency in $tsModuleNames) {
      $packageJsonPath = "$(get-absoluteprojectpath $dependency)/package.json";
      $packageJson = get-content $packageJsonPath | convertfrom-json;
      foreach($dep in ($packageJson.dependencies.PSObject.Properties + $packageJson.devDependencies.PSObject.Properties)) {
        $nodeModules += "$($dep.Name)@$($dep.Value.Replace('^',''))";
      }
    }

    $finalResult = @();

    foreach($module in ($nodeModules | get-unique | sort-object)) {
      if(!($installedNpmPackages -contains $module)) {
        $finalResult += $module;
      }
    }
    $finalResult;
  }

  function Restore-WcProject {
    <#
      .SYNOPSIS
        Restores all NPM and ts_references for a project.  If no project is provided, will run a restore operation on the entire solution.
    #>
    param(
      # The name of the project to restore.  If not provided, the whole solution will be restored.
      [string]$projectName, 
      # If this flag is provided, it will not invoke npm operations.  Speeds things up, but at the expense of not picking up npm changes.
      [switch]$skipNpm, 
      # Use this if you're trying to troubleshoot something.
      [switch]$verbose
    )
    $sln = get-wcsln;

    $projects = $(if($projectName) { get-wcproject $projectname } else { $sln.projects });

    foreach($project in $projects) { 
      if(!$skipnpm) {
        restore-npm $project.name;
      }
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
        Write-Host "Pulling $dependenciesAsString into [$($project.name)]."

        get-childitem $destination -recurse -erroraction silentlycontinue | remove-item -force -recurse -erroraction SilentlyContinue;
        remove-item $destination -recurse -force -erroraction silentlycontinue;
        new-item -ItemType Directory $destination -erroraction SilentlyContinue | out-null;

        if(!$skipNpm) {
          $missingTsModuleNpmPackages = get-missingtsmodulenpmpackages $project.name ($dependencies | where { $_.GetType().Name -eq 'String' });

          if($missingTsModuleNpmPackages.Count -gt 0) {
            $currentLocation = get-location;
            set-location $thisProjectPath;
            $command = "npm i $([string]::Join(' ', $missingTsModuleNpmPackages)) --no-save --no-package-lock";
            Write-Host "Restoring tsmodules npm packages."
            Write-Host $command;
            Invoke-Expression $command;
            set-location $currentLocation;
          }
        }

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
        }

        get-childitem '*.ts' -path "$thisProjectPath/ts_modules" -recurse |
        foreach-object { 
          (get-content $_ -raw) -replace '../ts_modules','../../ts_modules' | 
          out-file -filepath $_ -encoding 'UTF8' 
        }
      }
      else {
        Write-Output "[$($project.name)] has no ts_modules dependencies.  Skipping."
        mkdir $destination
      }
    }
  }

  function Get-WcSln() {
    <#
      .SYNOPSIS
        Provides a deserialized representation of your sln.json file.
    #>
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

  function Connect-WcProject(
    # The name of your project.
    [parameter(Mandatory=$true)][string]$projectName, 
    # The type of your project.  Valid values are lib, test, api, and ui.
    [string][Parameter(Mandatory=$true)]$projectType, 
    # Optionally integrate with mongoDB.  API projects only.
    [switch]$mongo) {
    <#
      .SYNOPSIS
        Adds a pre-existing project to your sln.json file.
    #>
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
  function Disconnect-WcProject([string][Parameter(Mandatory=$true)]$projectName) {
    <#
      .SYNOPSIS
        Removes a wcproject from your sln.json, but does not remove the source code.
    #>
    $sln = get-wcsln;
    $sln.projects = $sln.projects | where-object Name -ne $projectName;
    
    update-wcsln $sln;
  }
  function New-WcProject(
    # The name of your project.
    [Parameter(Mandatory=$true)]$projectName, 
    # The type of your project.  Valid values are lib, test, api, and ui.
    [string]$type = 'lib', 
    # Optionally integrate with mongoDB.  API projects only.
    [switch]$mongo, 
    # Optionally specify a port between 30000 and 31000 to use on your kind cluster for debugging.  If not specified, will analyze /.vscode/launch.json and auto-increment.  API projects only. 
    [int32]$debugPort = -1
  ) {
    <#
    .SYNOPSIS
        Creates a new WcProject.

    .DESCRIPTION
        Creates a new wcproject and adds an entry in your sln.json file for you.
    .EXAMPLE
        new-wcproject my-core-project
    .EXAMPLE
        new-wcproject testproj test
    .EXAMPLE
        new-wcproject my-new-api api -mongo -debugport 30123
    .NOTES
        Detail on what the script does, if this is needed.

    #>
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

      restore-wcproject $projectName;

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
    <#
      .DESCRIPTION
        Cleans out build artifacts from your project or entire solution.
    #>
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
    <#
      .DESCRIPTION
        Takes your API or UI's artifacts and pushes them to its associated kubernetes pod without reloading the pod.  Used internally by watch-wcproject.
    #>
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
  function Build-WcProject {
    <#
      .SYNOPSIS
        Builds your project and packages it into a Docker container if a UI or API project.
    #>
    param(
      # The name of the project to build.  If not provided, the whole solution will be built.
      [string]$projectName, 
      # If provided, a compatibility build will be included alongside your regular build.  Use this if you need to support old browsers like Internet Explorer.
      [switch]$compat, 
      # Using this flag will minify your code, strip out any comments, and remove any sourcemaps.  Only for UI projects.
      [switch]$optimize, 
      # Using this flag will skip running npm operations.  This will speed up the process, at the expense of not updating all of your packages.
      [switch]$skipNpm, 
      # Optionally provide a custom dockerfile.  If not provided, it will use "Dockerfile" at the root of your project directory.
      $dockerfile, 
      # Optionally skip packaging your built assets into a container.
      [switch]$skipContainer, 
      # Optional ScriptBlock that allows you to define custom behavior after building but before packaging into a container.  Ignored if -skipContainer is provided.
      [ScriptBlock]$preContainerActions
    )
    $projects = if($projectName) { @(get-wcproject $projectName) } else { (get-wcsln).Projects };

    foreach($project in [array]($projects)) {
      restore-wcproject $project.name -skipnpm:$skipnpm;

      $projectPath = get-absoluteprojectpath $project.name;
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
            if($lastexitcode -ne 0) {
              throw "tsc command exited with exit code $lastexitcode.";
            }

            Write-Host "- Running browserify for [$($compilation.name)] into $($compilation.outFile)";
            & "$projectPath/node_modules/.bin/browserify$cmdExtension" "$projectPath/src/index.js" --outfile $compilation.outFile $(if(!$optimize) { "--debug" });

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

        $postBuildPath = "$projectpath/automation/postBuild.ps1";
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

  function Export-ProdAssets {
    <#
      .SYNOPSIS
        Takes your built UI project and packages it up for production.  Use in Build-Wcproject in conjunction with the -Dockerfile and -PrebuildActions parameters.
      .DESCRIPTION
        Takes all of the assets in your dist folder and then prepares it for production use.  This includes replacing any instance of "build_number" in your source code and replacing it with a build.
        Also will insert a "build_environment" global javascript variable in your root index.html.

        Finally, ensures that only non-development NPM packages are present, and strips out any artifacts that are not registered in your project's prodAssets in sln.json.

        Only for UI projects.
      .EXAMPLE
        Build-WcProject my-project -dockerfile Dockerfile_prod -optimize -preContainerActions { Export-ProdAssets my-project -gzip }
    #>
    param(
      # The name of your project.
      [parameter(Mandatory=$true)][string]$projectName, 
      # Optionally provide a custom build number.  If not provided, it will get the current time in UTC Ticks.
      $buildNumber = (get-date).Ticks, 
      # Optionally provide a build environment name.  Defaults to 'prod'.
      [string]$environment = 'prod', 
      # Optionally gzip all of your artifacts.  It is highly recommended to gzip your assets at build time such as now rather than relying on your HTTP server to dynamically gzip for you.
      [switch]$gzip
    )
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
            $_fqExportLocation = (resolve-path $exportLocation).path;
            $fqExportLocation = "$_fqExportLocation/$(split-path $prodasset)"
            Write-Host "$prodassetpath --> $fqExportLocation";

            if(!(test-path $fqExportLocation)) {
              mkdir -p $fqExportLocation;
            }
            copy-item $prodassetPath $fqExportLocation -recurse -force;
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
 
  function Watch-Wcproject([string][parameter(Mandatory=$true)]$projectName) {
     <#
      .SYNOPSIS
        Watches a project for changes and auto-updates its corresponding container in your local development cluster.
      .DESCRIPTION
        Uses the command-line tool entr to watch for file changes.  Excludes watching .d.ts, .d.ts.map, and .js files.
        When a change is detected, it will rebuild your wcproject and sync the file changes with your container.
      .PARAMETER projectName
        The name of the project to watch.  Only API and UI projects are supported.
    #>
    $project = get-wcproject $projectName;

    if($project) {
      if($project.type -eq 'api' -or $project.type -eq 'ui') {
        $path = get-absoluteprojectpath $project.name;
        while($true) {
          get-childitem -recurse -path $path -exclude '*.d.ts','.*.d.ts.map','*.js' |
            select -expandproperty fullname |
            entr -d -s "pwsh -c 'import-module $psscriptroot/wc.psm1; build-wcproject $($project.name) -skipcontainer -skipnpm; sync-devpod $($project.name)'"
        }
      }
      else {
        throw "Only API or UI projects are watchable, as they are the only ones that run in a container.";
      }
    }
  }
  function Start-WcProject {
    <#
      .DESCRIPTION
        Builds, packages, and pushes your API or UI project to the local kubernetes cluster (kind).
    #>
    param(
      # The name of your project.
      [parameter(Mandatory=$true)]$projectName, 
      # If you just need to deploy your assets to kind without rebuilding it, provide this flag.
      [switch]$skipBuild, 
      # If you have any custom behavior that you'd like to execute INSTEAD OF "build-wcproject $projectName", provide that here.  Ignored if -skipBuild is provided.
      $customBuildBlock
    )
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
  function Remove-Wcproject([string][Parameter(Mandatory=$true)]$name, [switch]$force) {
    <#
      .SYNOPSIS
        Remove a wcproject from your solution, and delete the source code from disk.
    #>
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

  Export-ModuleMember New-WcProject, Get-TsDependencies, Watch-Wcproject, Connect-WcProject, Remove-Wcproject, Disconnect-WcProject, Get-WcSln, Restore-WcProject, Restore-Npm, Build-WcProject, Get-WcProject, Export-ProdAssets, Start-WcProject, Clear-WcProject, Add-MongoSecrets, Sync-DevPod, Get-InstalledNpmPackages;