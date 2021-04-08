$tarFile = "docker-18.03.1-ce.tgz";
invoke-webrequest "https://download.docker.com/linux/static/stable/x86_64/$tarFile" -outfile $tarFile
tar xzvf $tarFile --strip 1 -C /usr/local/bin docker/docker;
rm $tarFile;

get-command docker -erroraction stop;