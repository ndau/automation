FROM node:10
# JSG WIP Dockerfile for minikube install
# Create app directory
# WORKDIR /usr/src/app

# get kubectl and minikube in container

RUN apt-get update && apt-get install sudo

RUN curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && chmod +x minikube && cp minikube /usr/local/bin/ && rm minikube
RUN curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && cp kubectl /usr/local/bin/ && rm kubectl

# set up kubectl config file
RUN export MINIKUBE_WANTUPDATENOTIFICATION=false
RUN export MINIKUBE_WANTREPORTERRORPROMPT=false
RUN export MINIKUBE_HOME=$HOME
RUN export CHANGE_MINIKUBE_NONE_USER=true
RUN mkdir -p $HOME/.kube
RUN touch $HOME/.kube/config

RUN export KUBECONFIG=$HOME/.kube/config

# get docker in container
RUN curl -fsSL get.docker.com -o get-docker.sh
RUN sh get-docker.sh

# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY ./testnet/chaos.js ./

RUN VERSION_TAG=${git_sha} ./chaos.js 30000 castor pollux
# If you are building your code for production
# RUN npm install --only=production

# Bundle app source
COPY . .

EXPOSE 8080
CMD [ "npm", "start" ]