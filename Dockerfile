FROM mcr.microsoft.com/powershell

COPY . /src
RUN apt update
RUN pwsh -C 'get-childitem install-*.ps1 -path /src/automation/tools/ | % { & $_ }'
