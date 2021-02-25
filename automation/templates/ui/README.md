# _REPLACE_ME_ #

## Folder Structure ## 

### automation ###
*publish.ps1* - Automation that makes it easy to push your docker container to a docker registry.  Makes sure to minify and gzip your content before placing it in a Docker container, ready for production use.

### K8s ###
Contains all of the kubernetes configuration for deploying either to local or production. By default, creates an ingress controller that responds to requests on /_SOLUTION_NAME_/_REPLACE_ME_/ .

Prod contains some example production configuration, but should be fine tuned for your particular use case.

### nginx ###
Your UI application is hosted on nginx by default.  This folder contains the configuration files that will be used on your different environments. By default, the prod.conf file assumes that all of your content is gzipped (as performed in automation/publish.ps1).

### src ###
Your source code should go here.

### Dockerfile ###
Dockerfile used to build your local UI image.  The UI application is hosted in an nginx server that will serve your static content.

### Dockerfile_prod ###
The same as the regular Dockerfile, although it expects your static content to have been gzipped by a prior build step. Refer to automation/publish.ps1 for more information.

### Prodassets ###
Only assets defined in your project's sln.json prodAssets field will be included in the final production build.  This is to avoid bloated node_modules folders and the like.
If adding a new folder outside of what's already included in the out of the box template, please make sure to refer to your sln.json and ensure that the prodAssets is configured
to your needs.