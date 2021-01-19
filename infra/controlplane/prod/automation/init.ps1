import-module "$psscriptroot/../../../../automation/wc.psm1";
kubectl create namespace (get-wcsln).name;