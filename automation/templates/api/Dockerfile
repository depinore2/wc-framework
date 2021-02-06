FROM node:14.15.1-slim

RUN npm install nodemon -g

COPY ./src /app/src
COPY ./ts_modules /app/ts_modules
COPY ./node_modules /app/node_modules

ENV PORT=80
WORKDIR /app/src
CMD ["node", "--inspect=0.0.0.0:9229", "."]