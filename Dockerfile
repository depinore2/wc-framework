FROM mcr.microsoft.com/powershell

RUN apt update
RUN pwsh -C 'get-childitem install-*.ps1 -path /src/automation/tools/ | % { & $_ }'
COPY . /src