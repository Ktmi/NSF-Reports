---
title: "Milestone 3: Working with Kytos, Docker, and Kubernetes"
...

# Introduction

The purpose of this project is to be able to orchrestrate running
Kytos in a Kubernetes cluster, with access to its API
protected by a proxy.
In order to complete this project, I divided into the following
tasks:

 - [Setting Up the Environment]
 - [Creating Docker Images]
 - [Deploying to Kubernetes]

# Setting Up the Environment

Before the main work of the project could be completed,
I would need to setup a development environment.
The main components of this environment are
the Kubernetes Cluster, and the Docker registry.

## Creating a Kubernetes Cluster

In order to test my Kubernetes deployments,
I created a Kubernetes cluster.
The cluster consists of 2 nodes,
1 worker, and 1 master node.
Both nodes are virtual machines,
with 2 CPU cores and 4 GiBs of RAM assigned,
running CentOS 7.
For more information on how I created my Kubernetes Cluster,
please see the included guide [How to Create a Kubernetes Cluster].

## Running a Docker Registry

In order to make any Docker images I created for this project
available to my cluster, I deployed a private Docker registry.
The Docker registry was deployed to my Kubernetes cluster,
which should **NOT BE DONE IN A PRODUCTION ENVIRONMENT**.
For more information on how I deployed my Docker registry,
please see the included guide [How to Deploy a Docker Registry to Kubernetes].
For the purpose of this project, the Docker registry will be available at `localhost:30001` for all nodes in the cluster.

# Creating Docker Images

Creating Docker images, while not a requirement for this project,
serves as an example for why to create  custom Docker images.

## Kytos Image

The first image I created was for Kytos.
The standard Kytos image, `kytos/nightly` has no NApps installed,
and installing NApps at runtime would require reinstalling them every time
the container is restarted.
To remedy this, the Docker image can be rebuilt with the desired NApps installed.

### Installing NApps

Normally to install NApps, the Kytos server needs to be running.
However when building a Docker image, we are usually limited to executing
one command at a time, making installing through Kytos not an option.
Alternatively, NApps can be installed through `pip` without needing
to concurrently run any other program.
Installing with `pip` also allows for installing directly from git repositories.
To install an NApp from its git repository, run the following command:

```bash
pip install -e git+http://$NAPP_REPO#egg=$NAPP_NAME
```

Where `$NAPP_REPO` is a link to the git repository for the NApp,
and `$NAPP_NAME` is the name of the NApp.

### Dockerfile

For the Kytos image, I created the following Dockerfile:

```Dockerfile
# Use kytos/nightly as base image
FROM kytos/nightly
# Install NApps
RUN pip install -e git+http://github.com/kytos/storehouse#egg=storehouse
RUN pip install -e git+http://github.com/kytos/of_core#egg=of_core
RUN pip install -e git+http://github.com/kytos/flow_manager#egg=flow_manager
RUN pip install -e git+http://github.com/kytos/topology#egg=topology
RUN pip install -e git+http://github.com/kytos/of_lldp#egg=of_lldp
RUN pip install -e git+http://github.com/kytos/pathfinder#egg=pathfinder

# The following NApps do not work with this install method
# RUN pip install -e git+http://github.com/kytos/mef_eline#egg=kytos_mef_eline
# RUN pip install -e git+http://github.com/kytos/maintenance#egg=kytos-maintenance
```

The Dockerfile uses `kytos/nightly` as the base image, then installs the following NApps:

 - kytos/storehouse
 - kytos/of_core
 - kytos/flow_manager
 - kytos/topology
 - kytos/of_lldp
 - kytos/pathfinder

## HTTPD Proxy Image

When deploying an application with Kubernetes,
usually the configuration is done by mounting configuration files
onto the container. However, if the configuration is something that will
be replicated many times over, then it could be preferable to integrate
the configuration directly into the Docker image.
For HTTPD, I believed that setting up an SSL proxy with authentication
wouldn't be that uncommon a task.

### HTTPD Configuration

To avoid having to create a new `httpd.conf` file for every new
deployment, the configuration file uses environment variables.
The following environment variables are used:

 - `$SERVER_NAME` - Name of the server
 - `$UPSTREAM_LOCATION` - Upstream server we are running a proxy for
 - `$AUTH_REALM` - The authentication realm of the server.

The following is a snippet of the `httpd.conf` file used in the Docker image:

```apache
# Other configuration stuff
...

# Listen on port 443
Listen 443
# Create ssl enabled virtual host at port 443
<VirtualHost *:443>
    SSLEngine on
    SSLCertificateFile "${HTTPD_PREFIX}/cert/certificate.cert"
    SSLCertificateKeyFile "${HTTPD_PREFIX}/cert/certificate.key"

    # Server name from environment variable $SERVER_NAME
    ServerName "${SERVER_NAME}"

    # Proxy pass to root of virtual host
    ProxyPreserveHost On
    # Upstream server location from environment variable $UPSTREAM_LOCATION
    ProxyPass / "${UPSTREAM_LOCATION}"
    ProxyPassReverse / "${UPSTREAM_LOCATION}"

    # Require authentication for root of virtual host and all sub directories.
    <Location "/">
        AuthType Basic
        AuthName "${AUTH_REALM}"
        AuthUserFile "${HTTPD_PREFIX}/access/.htpasswd"
        Require valid-user
    </Location>
</VirtualHost>
```

SSL certifcations and password files for authentication still must be mounted
to the container.
The SSL and password files should be mounted to the following locations:

 - SSL certificate file - `/usr/local/apache2/cert/certificate.cert`
 - SSL certificate key file - `/usr/local/apache2/cert/certificate.key`
 - Password file - `/usr/local/apache2/access/.htpasswd`

### Dockerfile

The httpd proxy image is built from the following Dockerfile:

```Dockerfile
FROM httpd:2.4

COPY ./httpd-proxy.conf ${HTTPD_PREFIX}/conf/httpd.conf
```

The Dockerfile uses `httpd:2.4` as the base image,
then copies `httpd-proxy.conf` into the image.

# Deploying to Kubernetes



## Kytos Deployment

Kytos requires two services to expose ports for the server.
One service exposes the kytos api internally, the other exposes
Openflow externally. The following file creates a deployment for Kytos:

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kytos-controller
  labels:
    app: kytos
spec:
  selector:
    matchLabels:
      app: kytos
      role: controller
  replicas: 1
  template:
    metadata:
      labels:
        app: kytos
        role: controller
    spec:
      containers:
      - name: controller
        image: localhost:30001/kytos
        command: ["/bin/bash", "-c", "kytosd; sleep infinity"]
        ports:
        - containerPort: 8181 # API Port
        - containerPort: 6653 # Open Flow Port
```

The deployment runs the Kytos image that I created.
It starts the Kytos daemon, then puts the foreground
process into infinite sleep.
Putting the system into infinite sleep, or any other method of endless
waiting, prevents the container from terminating due to a lack of foreground processes.

The following file creates a service exposing the kytos api:

```yml
apiVersion: v1
kind: Service
metadata:
  name: kytos-api
  labels:
    app: kytos
    role: api
spec:
  ports:
  - port: 80
    targetPort: 8181
  selector:
    app: kytos
    role: controller
```

The service adds the dns entry `kytos-api` to the cluster.
This service redirects requests to  `kytos-api:80`
to port 8181 of pods with the labels `app=kytos,role=controller`.

The following file creates a service exposing the Openflow port of the Kytos controller:

```yml
apiVersion: v1
kind: Service
metadata:
  name: kytos-openflow
  labels:
    app: kytos
    role: openflow
spec:
  type: NodePort
  ports:
  - port: 6653
    targetPort: 6653
    nodePort: 30003
  selector:
    app: kytos
    role: controller
```

The service adds the dns entry `kytos-openflow` to the cluster.
This service redirects requests to `kytos-openflow:6653`
and requests to any node at port 30003
to port 6653 of pods with the labels `app=kytos,role=controller`.


## Proxy Deployment

The following file generates the Kubernetes secrets necessary for running the proxy:

```bash
openssl genrsa -des3 -passout pass:x -out certificate.pass.key 2048
openssl rsa -passin pass:x -in certificate.pass.key -out certificate.key
openssl req -new -key certificate.key -out certificate.csr
openssl x509 -req -sha256 -days 365 -in certificate.csr -signkey certificate.key -out certificate.cert

kubectl delete secret ssl-cert
kubectl create secret generic ssl-cert --from-file=./certificate.key --from-file=./certificate.cert

kubectl delete secret kytos-access
kubectl create secret generic kytos-access --from-file=./.htpasswd
```

This file will generate two Kubernetes secrets.
The first secret generated is for SSL certificates for the proxy.
The second secret is pasword/authentication info for the proxy,
which is generated from the file `.htpasswd`.


The following file creates the deployment for the proxy:

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpd-proxy
spec:
  selector:
    matchLabels:
      app: httpd
      role: proxy
      tier: frontend
  replicas: 1
  template:
    metadata:
      labels:
        app: httpd
        role: proxy
        tier: frontend
    spec:
      containers:
      - name: proxy
        image: localhost:30001/httpd-proxy
        env:
        - name: UPSTREAM_LOCATION
          value: "http://kytos-api:80/"
        - name: SERVER_NAME
          value: "kytos-proxy"
        - name: AUTH_REALM
          value: "kytos"
        volumeMounts:
        - name: ssl-cert
          mountPath: "/usr/local/apache2/cert"
          readOnly: true
        - name: access
          mountPath: "/usr/local/apache2/access"
          readOnly: true
      volumes:
      - name: ssl-cert
        secret:
          secretName: ssl-cert
      - name: access
        secret:
          secretName: kytos-access
```

The deployment runs the httpd-proxy image I created.
It mounts the secret for the ssl certificates `ssl-cert` and the secret for
passwords `kytos-access` to the container.
`$UPSTREAM_SERVER` is set to `http://kytos-api:80/`,
`$AUTH_REALM` is set to `kytos`,
and `$SERVER_NAME` is set to `kytos-proxy`.

The following file creates a service for exposing the proxy externally:

```yml
apiVersion: v1
kind: Service
metadata:
  name: kytos-proxy
  labels:
    app: kytos
    role: proxy
spec:
  type: NodePort
  ports:
  - port: 443
    targetPort: 443
    nodePort: 30002
  selector:
    app: httpd
    role: proxy
    tier: frontend
```

The service adds the dns entry `kytos-proxy` to the cluster.
This service redirects requests to `kytos-proxy:443`
and requests to any node at port 30002
to port 443 of pods with the labels `app=httpd,role=proxy,tier=frontend`.

# Guides

The following is a set of guides/procedures for setting up critical components for this project.

## How to Create a Kubernetes Cluster

This guide covers the procedures used for creating the Kubernetes cluster.
For this project a Kubernetes cluster was required to test deploying Kytos.
Rather than using the services of a public cloud provider for a Kubernetes cluster, I instead created a cluster on a set of Linux VMs.

The following procedures are based on the procedures at this [link][Original Cluster Procedures].
These procedures assume that all nodes within the cluster are running CentOS 7,
and that all commands are executed as `ROOT`.
If you are following along with these procedures and are not `ROOT`,
you can do so by executing `sudo su`.

[Original Cluster Procedures]: https://github.com/justmeandopensource/kubernetes/blob/master/docs/install-cluster-centos-7.md "Install Kubernetes Cluster using kubeadm"

### Setting Up Prerequisites and Installing Kubernetes

The procedures covered in this section will have to be repeated for every node
to be added into the cluster.

To begin, firewalld, SELinux, and swap memory need to be disabled. To do so, run the following set of commands:

```bash
systemctl disable firewalld; systemctl stop firewalld
setenforce 0
sed -i --follow-symlinks 's/^SELINUX=enforcing/SELINUX=disabled/' \
/etc/sysconfig/selinux
swapoff -a; sed -i '/swap/d' /etc/fstab
```

Kurbernets needs a container runtime to work. For this project,
I used Docker Engine as the container runtime. To install Docker Engine, run the following set of commands:

```bash
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce-19.03.12 
```

After installing Docker I reconfigured it to use `systemd` as its cgroup driver. Once completed, I then enabled Docker.
To configure, then enable docker, run the following set of commands:

```bash
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload
systemctl enable --now docker
```

After installing, configuring, and enabling docker, I installed Kubernetes.
To install Kubernetes, run the following set of commands:

```bash
cat >>/etc/yum.repos.d/kubernetes.repo<<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
yum install -y kubeadm-1.18.5-0 kubelet-1.18.5-0 kubectl-1.18.5-0
```

When Kubernetes was installed, I then changed the sysctl settings for kubernetes networking to work. After changing and enabling these settings,
I then enable the kubelet so I can use Kubernetes.
To change the necessary sysctl settings and enable kubelet,
run the following set of commands.

```bash
cat >>/etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
systemctl enable --now kubelet
```

### Creating the Master Node

After installing Kubernetes with Docker on all of the nodes,
I created the master node. To initialize the master node,
run the following command:

```bash
kubeadm init --apiserver-advertise-address=$IP_ADDR --pod-network-cidr=$IP_CIDR
```

For this command to execute, the variabes in the command should be
set according to the following:

 - `$IP_ADDR` is the IP address where the master node will be accessed at.
 - `$IP_CIDR` is the range of IPs the cluster will use for assigning to pods and services.

### Controlling the Cluster

Any system which is to interact with the Kubernetes API of the Cluster,
needs to have keys from the master node.
Upon creation of the master node,
Kubernetes generates a set of keys for an administrator,
storing them to the config file `/etc/kubernetes/admin.conf`.
The config from the master node can be copied to other systems, into the file
`~/.kube/config`, allowing for accessing the api through `kubectl`.

### Installing a Network Plugin to the Cluster

In order to facilitate communications between pods,
a network plugin needs to be installed.
For this project I used Project Calico.
To install Project Calico to the cluster,
run the following command:

```bash
kubectl create -f https://docs.projectcalico.org/v3.14/manifests/calico.yaml
```

### Adding Worker Nodes

In order to add a worker node to the cluster,
the worker needs to have a join token from the master.
To generate a join token, run the following command on the master node:

```bash
kubeadm token create --print-join-command
```

The command will generate a join token,
then print a command for the join token.
Entering the command into a worker node will have it join the cluster.

### Additional Notes

There are several more nuanced aspects of setting up a Kubernetes Cluster that I did not conduct.
The following is a list of additional things that could be done while setting up a cluster:

 - Buil a multi-node control plane, so as to keep the cluster highly available.
 - Implement role-based access control, to set who can modify what on the cluster.
 - Configuring networking for improved security.

## How to Deploy a Docker Registry to Kubernetes

This guide covers the process used for deploying a private docker
registry for this project.
This method for running a Docker registry is
**NOT SUITABLE FOR PRODUCTION ENVIRONMENTS**
as the docker registry would be unprotected from external access.

The purpose of running a Docker registry is to provide access
to Docker images produced as part of the project.
Having images available through a local registry reduces
external network traffic produced from pulling images
from an external public registry.

In order to make the docker images created during this project available
to the Kubernetes cluster, the images would need to be pushed to a docker
registry.
Rather than using a public registry, I instead opted to create my own private
registry on the cluster.

### Registry Deployment

In order to deploy the registry to a kubernetes cluster,
I created the following file, which describes the deployment.

```yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry-backend
  labels:
    app: docker-registry
    role: backend
spec:
  selector:
    matchLabels:
      app: docker-registry
      role: backend
  replicas: 1
  template:
    metadata:
      labels:
        app: docker-registry
        role: backend
    spec:
      containers:
      - name: backend
        image: registry:2
        ports:
        - containerPort: 5000
```

### Registry Service

In order to make the registry accessible to the cluster,
I created the following service:

```yml
apiVersion: v1
kind: Service
metadata:
  name: local-registry
  labels:
    app: docker-registry
    role: access
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 5000
    nodePort: 30001
  selector:
    app: docker-registry
    role: backend
```

This service makes the docker registry available at `docker-registry:80`
on the cluster,
and allows for it to be externally accessed at port `30001` on any node on the cluster.

### Building Docker Images

To build a Docker image from a Dockerfile,
run the following command:

```bash
docker build . -t $TAG_NAME
```

Where `$TAG_NAME` is the name used to identify the image.

### Pushing and Pulling Images From a Private Registry

In order to to push an image to a registry,
it has to be within the local cache of the machine you are pushing from.
Images can be stored into the local cache,
either by building an image or pulling from a repository.
To pull from docker hub, run the following command:

```bash
docker pull $SOURCE_IMAGE
```

Where `$SOUCE_IMAGE` is the tag of the image desired.

Before images can be pushed, they need to be tagged with
the address of the registry they will be pushed to.
To create a new tag that corresponds to an existing image,
run the following command.

```bash
docker tag $SOURCE_IMAGE $DOCKER_REGISTRY/$TARGET_TAG
```

Where `$SOURCE_IMAGE` is the original tag for the image,
`$DOCKER_REGISTRY` is the address of the docker registry,
and `$TARGET_NAME` is the tag of the image on the registry.

By prepending the address of the docker registry to the new tag
for the image, it can then be pushed to the registry at that address.
To push the image to a registry, run the following command:

```bash
docker push $DOCKER_REGISTRY/$TARGET_TAG
```

Where `$DOCKER_REGISTRY` is the address of the docker registry,
and `$TARGET_NAME` is the tag of the image on the registry.

To use use the image from the private registry, the tag with the
docker registry appended to it should be referenced instead.
To pull the image from the docker registry into your local cache,
run the following command:

```bash
docker pull $DOCKER_REGISTRY/$TARGET_TAG
```

Where `$DOCKER_REGISTRY` is the address of the docker registry,
and `$TARGET_NAME` is the tag of the image on the registry.

### Additional Notes

The method of deploying a Docker registry presented in this guide,
is not suitable for production environments.
An alternative, safer method of deploying a registry
would be to deploy it seperate from the cluster,
only accessible through a private network.

# References

To get a better understanding of the topics necessary to conduct this project,
I read the following guides and documentation:

 - [Original Cluster Procedures]
 - [Kubernetes Documentation]
 - [Docker Documentation]

[Kubernetes Documentation]: https://kubernetes.io/docs/home/
[Docker Documentation]: https://docs.docker.com/

## Source files

For the source files for this project please see the repository at this [link][Project Git].

[Project Git]: https://github.com/Ktmi/NSF-Milestone3