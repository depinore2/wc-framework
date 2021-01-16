# place custom automation you'd like to run before Start-Wcproject in this file.
param($apiName = '_REPLACE_ME_')
& "$psscriptroot/addMongoCreds.ps1" $apiName;