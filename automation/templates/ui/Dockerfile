FROM nginx:1.19

# this file will be executed as the default (for local development).  
# Due to that, just copy the whole project's source code into the container for source map support.
COPY . /usr/share/nginx/html
COPY nginx/local.conf /etc/nginx/nginx.conf