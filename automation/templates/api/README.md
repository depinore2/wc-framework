# _REPLACE_ME_ #

## Folder Structure ## 

### automation ###
*addMongoCreds.ps1* - Automation that deploys mongodb credentials to a k8s cluster in the event you want to hook mongodb into your API.

*publish.ps1* - Automation that makes it easy to push your docker container to a docker registry.

*preBuild, postBuild, preStart, postStart* - wc pipeline hooks that allow you to define custom behavior at each stage of the project build and run process.  Refer to the solution-level README for more information.

### K8s ###
Contains all of the kubernetes configuration for deploying either to local or production. By default, creates an ingress controller that responds to requests on /_SOLUTION_NAME_/_REPLACE_ME_/ .

The local configuration assumes that you want to expose port 9229 for debugging purposes.

Prod contains some example production configuration, but should be fine tuned for your particular use case.

### src ###
Your source code should go here.

### Dockerfile ###
Dockerfile used to build your local API image.  By default, allows incoming connections from any host and runs it within nodemon.  Exposes port 9229 so that you can attach a debugger.

### Dockerfile_prod ###
Example dockerfile that could be used in production.