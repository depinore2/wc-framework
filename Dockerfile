FROM mcr.microsoft.com/powershell

RUN apt update
COPY . /src
RUN pwsh -C 'get-childitem install-*.ps1 -path /src/automation/tools/ | % { & $_ }'