param([Parameter(Mandatory=$true)][string]$publishedContainerName, $projectName = '_REPLACE_ME_')
import-module "$psscriptroot/../../../automation/wc";

$solutionName = (get-wcsln).name;

Build-WcProject _REPLACE_ME_ -dockerfile "$psscriptroot/../Dockerfile_prod" -optimize -preContainerActions { export-prodassets _REPLACE_ME_ (get-date).Ticks 'prod' -gzip }
docker tag "wc_$($solutionName)_$($projectName):local" $publishedContainerName;
docker push $publishedContainerName;