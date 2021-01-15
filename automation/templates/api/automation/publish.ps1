param([Parameter(Mandatory=$true)][string]$publishedContainerName, $projectName = '_REPLACE_ME_')

# Put any custom automation you'd like to run to publish to a remote environment here.  (Such as to deploy to production.)
import-module "$psscriptroot/../../../automation/wc";

$solutionName = (get-wcsln).name;

build-wcproject $projectName -dockerfile "$psscriptroot/../Dockerfile_prod"
docker tag "wc_$($solutionName)_$($projectName):local" $publishedContainerName;
docker push $publishedContainerName;