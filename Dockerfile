FROM mcr.microsoft.com/powershell

ENV TZ=America/Los_Angeles

RUN apt update
RUN apt-get install ca-certificates -y
COPY ./automation /src/automation
RUN pwsh -File "/src/automation/tools/install-docker.ps1"
RUN pwsh -File "/src/automation/tools/install-entr.ps1"
RUN pwsh -File "/src/automation/tools/install-git.ps1"
RUN pwsh -File "/src/automation/tools/install-kind.ps1"
RUN pwsh -File "/src/automation/tools/install-kubectl.ps1"
RUN pwsh -File "/src/automation/tools/install-node.ps1"
RUN pwsh -File "/src/automation/tools/install-psmodules.ps1"
COPY . src
COPY ./powershellProfile.ps1 /root/.config/powershell/Microsoft.PowerShell_profile.ps1