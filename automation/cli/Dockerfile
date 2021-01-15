FROM mcr.microsoft.com/powershell

# install mongo
RUN apt-get update
RUN apt-get install wget gnupg -y
RUN wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add -
RUN echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-4.4.list
RUN apt-get update
RUN apt-get install mongodb-org-shell -y

# copy all automation scripts into this image as well
COPY . /automation

# install other helpful tools
RUN apt-get install net-tools iputils-ping -y