# The wc Framework: Full-Stack TypeScript #

## Another Framework??? ##
The objective of this framework is to provide you with a way of building complex, full-stack TypeScript projects in a way that makes sense to .NET developers.  Your modules are "wcprojects", and your wcprojects are aggregated into a single "wcsln" ("sln" stands for "Solution", as in ".NET solutions".)  Wcprojects can reference one another via ts_modules, much like .NET project references.

A common scenario I run into is the need for a core library to be referenced by test, api, and ui projects--all with different compilation needs:
```
    core-lib
     ^ ^ ^
    /  |  \
test  api  ui
```

Solutions like [lerna](https://github.com/lerna/lerna) and [TypeScript Project References](https://www.typescriptlang.org/docs/handbook/project-references.html) are great, but I didn't like that the consuming project didn't have the ability to control how the referenced asset is compiled.  This can result in situations where your coreLibrary is compiled and works great in nodeJS, but fails to work properly in legacy browsers, for example.  

Instead of that approach, this framework uses the concept of ts_modules, which is discussed at greater length later in this README.

Disclaimer: I only ever develop using Windows 10, WSL2, and Docker Desktop with WSL2 enabled.  This theoretically works on macOS and Linux, but I'm a scumbag and didn't test it on either of those.  Be warned!

## Getting Started ##
Prerequisites:
* bash shell  
*If you are on Windows, you must [enable WSL2](https://www.omgubuntu.co.uk/how-to-install-wsl2-on-windows-10)*.
* Docker Desktop, with WSL2 Engine enabled if on windows.  
*On Windows, install WSL2 BEFORE installing Docker Desktop to avoid having to enable Hyper-V.*
* VS Code
* Remote Development VSCode Extension
* Containers Remote Development VSCode Extension

Ok, let's go!
1. Open `bash`.
2. Clone this repository.  Windows users: clone this repo into your Linux directory and *not* your Windows file system.
3. Open the repo in VS Code from your `bash` terminal.
4. VSCode should detect that you have a root-level Dockerfile and prompt you to reopen the folder in a container.  Click YES.
5. Wait a while...
6. When it finishes loading, change the name of your solution on Line 2 of sln.json to whatever you wish.
7. Start a `pwsh` terminal. All framework tooling is implemented using Powershell, so it's time to get comfortable with it. 
8. Spin up a brand new kubernetes control plane by executing: `./src/controlplane/local/automation/new-cluster.ps1`.  This uses Kubernetes In Docker (aka "[kind](https://kind.sigs.k8s.io/)").
9. Wait some more...
10. Your primary framework toolset can be found in the `wc` Powershell Module. Load the module by executing `import-module ./automation/wc` from the root of the repo.
11. Create a new UI project called test-drive by executing: `new-wcproject test-drive ui`.
12. Build it and deploy it to kubernetes by running `start-wcproject test-drive`
13. Navigate to http://localhost/test-drive .  You can optionally also use https and agree to the warnings issued by your browser.  You should see a demo SPA page saying It Works!
14. When done, go back to your terminal and run `remove-wcproject test-drive` to delete the project and remove its reference from sln.json.

## Project Types ##
To create a project, use `New-WcProject <projectName> [lib|test|api|ui]`.

This framework support 4 project types out of the box:

|Type|Description|
|---|---|
lib|A portable class library project, intended for use in other projects.|
|test|A unit test project scaffolded to use the mocha library.|
api|An expressJS project.|
ui|A Web Components SPA project.|

## Building Projects ##
To build a project use `Build-Wcproject [projectName]`.  If you don't provide a projectName, it will build all projects.  When you build a wcproject, the following occurs:

1. `Restore-WcProject [projectName]`, which runs
    1. `Restore-Npm [projectName]`
    2. `Restore-TsModules [projectName]`
2. `tsc` against the tsConfig.json of your project
3. Optionally `docker build` if your project is a server application (UI or API), named `docker.io/library/wc_{solutionName}_{projectName}:local`

For more information, refer to the `k8s/local.yaml` and `Dockerfile` files of your project.

## Running Projects ##
To run a project, use `Start-WcProject <projectName>`

This framework support 4 project types out of the box:

|Type|Behavior|
|---|---|
lib|Not runnable.|
|test|Runs all tests.|
api|Builds TypeScript, Builds `nodeJS:slim` Docker Container, deploys to kind.|
ui|Builds TypeScript, Builds an `nginx` Docker Container, deploys to kind.|

API and UI projects come with kubernetes manifest files pre-configured to deploy to `http://localhost/<project-name>` when you run it.

For example, if you have an api called `my-great-api`, on `Start-Wcproject my-great-api`, you can access it via `http://localhost/my-great-api`.  This pattern holds true for UI projects as well.

You can 

## ts_modules ##

The primary means of sharing code between your projects in this framework is via ts_modules.  A ts_module is a reference from one of your typescript projects to another.  When one project has a ts_module to another, it generates a copy of the referenced project's source code and makes a copy for itself.

For example, let's assume we have two projects: `projA` and `projB1`:
```
/
  sln.json
  src/
    projA/
      node_modules/
        dependencyA/
        dependencyB/
      src/
        helloWorld.ts
    projB/
      node_modules/
        dependency1/
        dependency2/
      src/
        index.ts
```
Next, let's assume that `projB` references `projA` like this in the `sln.json` at the root of the repository:
```
{
  {
    "name": "projA",
    ...
    "ts_modules": []
  }
  {
    "name": "projB",
    ...
    "ts_modules": [ "projA" ]
  }
}
```
When you build `projB`, it will insert a copy of `projA/src` into `projB` using the following template:
```
/src/{hostProj}/ts_modules/{referencedProj}
```
So that the resulting folder structure looks like this:
```
/
  sln.json
  src/
    projA/
      ...
      src/
        helloWorld.ts
    projB/
      ...
      src/
        index.ts
      ts_modules/
        projA/
          helloWorld.ts
```
Furthermore, any node_modules referenced in a referenced ts_module will also be brought over, so that the resulting folder structure looks like this:
```
/
  sln.json
  src/
    projA/
      node_modules/
        dependencyA/
        dependencyB/
      src/
        helloWorld.ts
    projB/
      node_modules/
        dependencyA/
        dependencyB/
        dependency1/
        dependency2/
      src/
        index.ts
      ts_modules/
        projA/
          helloWorld.ts
```
The value of doing things this way is that now you have the raw source code from your referenced modules, and can compile them in any way the host application needs it in.

This process works recursively, so if you reference something that also references something, all of them will be brought up to the top level in a flattened way.  Assuming `projC` --> `projB` --> `projA`, this is what `projC`'s folder structure would look like:

```
/
  ...
  projC/
    node_modules/
      dependencyA/
      dependencyB/
      dependency1/
      dependency2/
      dependencyX/
      dependencyY/
      dependencyZ/
    src/
      file1.ts
      file2.ts
    ts_modules/
      projA/
        helloWorld.ts
      projB/
        index.ts
  ...
```

Every time you recompile projB, it will re-fetch the latest version of `projA`.  Changes to `projA` do not reflect in `projB` until you recompile `projB`.

The default .gitignore that comes with this framework ignores ts_modules and node_modules folders.

Using a ts_module code is as easy as importing it.  Assuming `/src/projC/src/file1.ts` from the example above,
```
import * as helloWorld from '../../ts_modules/projA/helloWorld';
```
## Adding ts_modules to a Project ##
To add a ts_module reference from one project to another, you update the root-level sln.json. ("sln" in this context stands for "Solution", inspired by .NET sln project files.)

The syntax for adding a ts_module reference comes in two formats.  The simplest one is providing a string to the name of another project.  An example of that was provided above in the "How it Works" section. 

Here it is again:
```
{
  {
    "name": "projA",
    ...
    "ts_modules": []
  }
  {
    "name": "projB",
    ...
    "ts_modules": [ "projA" ]
  }
}
```
You can also use a long-form syntax that lets you fine-tune where you bring things in from, and how you bring them in.  Example:
```
"name: "my-project",
"ts_modules": [
  {
    "from": "node_modules/@depinore/wclibrary/src/", // required
    "to": "@depinore/wclibrary", // required
    "include": "*.ts", // optional; defaults to *.ts
    "exclude": "*.d.ts", // optional; defaults to *.d.ts
    "recurse": true // optional; defaults to true
  }
]
```
Using the above configuration and assuming the following project structure:
```
/
  src/
    my-project/
      node_modules/
        @depinore
          wclibrary/
            src/
              dir1/
                file1.ts
                file1.d.ts
                file1.js
              dir2/
                file2.ts
                file2.d.ts
                file2.js
              index.ts
              index.d.ts
              index.js
      src/
        index.ts
```
When you build `my-project`, the resulting ts_module structure will be:
```
/
  src/
    my-project/
      node_modules/
        @depinore/
          wclibrary/
            src/
              dir1/
                file1.ts
                file1.d.ts
                file1.js
              dir2/
                file2.ts
                file2.d.ts
                file2.js
              index.ts
              index.d.ts
              index.js
      src/
        index.ts
      ts_modules/

```

## Powershell Cmdlet Help ##
After importing the wc powershell module, please acquaint yourself with the various commands using `get-help` ([Microsoft Documentation](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-help?view=powershell-7.1)).
The most commonly-used commands are `start-wcproject`, `new-wcproject`, `watch-wcproject`, and `remove-wcproject`.  Start there!

## MongoDB Integration ##
This framework comes with some mongodb integration out of the box.  

### Bootstrapping MongoDB ### 
First thing you want to do is spin up a mongodb database that your microservices can utilize by running `/infra/mongo/automation/init.ps1`.  

You will need to provide it with an administrator username and password, and a configuration name that indicates which YAML configuration file it should use to configure it on kubernetes.  For local development, you'll want to use the `local` configuration.

An example of its usage: `./infra/mongo/automation/init.ps1 myUsername myPassword local`  .

This will create a mongodb endpoint on your local kubernetes cluster using development settings.  For more information, refer to `infra/mongo/k8s/local.yaml`.

Now that you have a mongodb endpoint, you can create new api projects with the `-mongo` flag.

### The `-mongo` Flag ###
When you create a new API project, you can optionally bootstrap it with mongodb integration using the `-mongo` flag.  

Example:
```
new-wcproject my-endpoint api -mongo
```
Assuming you have mongodb already initialized in your kubernetes cluster, using this flag will do the the following every time you `start-wcproject <projectName>`:

1. Check to see if unique credentials for your API already exist.  If so, it skips to step 4.
1. Create new credentials that will server as your microservice's username and password pair for mongodb.  The username will be of the format `<projectName>_user`, and the password will be a randomly-generated 200-character-long alphanumeric string.
1. Deploy these credentials to kubernetes as a "Basic Auth" Secret.
1. Check to see if mongodb already has a user named `<projectName>_user`.  If not, create the user using the username/password pair created in step 2.
5. Check to see if a database that matches `<projectName>` already exists.  If not, create the database and give `<projectName>_user` read/write access to it.
6. Build `<projectName>` and place it in a container.  
7. Push the container to kind.
8. Deploy a configuration YAML file to the kind control plane, which takes the username/password pair stored in kubernetes and exposes it as environment variables `MONGO_USERNAME` and `MONGO_PASSWORD`.  (Use `process.env` in nodeJS to create your mongodb connection in your code.)


## Why 'wc'? ##
This was originally just a framework for web components, but I got owned by scope creep. `¯\_(ツ)_/¯`