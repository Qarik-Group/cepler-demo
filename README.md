# Cepler demo

This repository serves as an introduction to the local usage of cepler.

## Introduction

When operating software it is common to have more than 1 deployment of your system running.
These deployments are typically segregated into multiple environments (such as dev / staging / production).
One goal here is to de-risk making changes to the production system where end-users may be effected.
By trying out software upgrades or config changes on a 'non-production' environment we can gain insights to what we expect to happen when we execute the same change on the production environment.

This approach is premised by the assumption that environments are identical to begin with (see [12factor.net/dev-prod-parity](https://12factor.net/dev-prod-parity) for more information).
In practice this is almost never the case, at a minmum because the production environment will necesarrily have real-world load that the other environments won't.
Nevertheless having multiple environments can go a long way in improving the stability of your production work-loads.

Managing multiple environments does introduce some complexity and operational overhead.
Questions that require answering by ops teams are typically:
- How do we inject environment specific configuration?
- When making changes - how do we ensure an orderly propagation of the changes from 1 environment to the next?

There are various patterns and best practices for dealing with this complexity that are coupled to specific ops toolchains.
Here I would like to introduce Cepler as a general tooling-independant solution to this problem.

## Setup

In this demo we will show how to use cepler to manage the shared and environment-specific configuration files needed to deploy software.
As a trivial example we will be deploying a container running nginx to kubernetes.

First you will need access to a kubernetes - for example via:
```
$ minikube start
(...)
$ kubectl get nodes
NAME       STATUS   ROLES    AGE   VERSION
minikube   Ready    master   23d   v1.19.0
```

The config files we will use are under the [./k8s](./k8s) directory.
To merge them together we will use [spruce](https://github.com/geofffranks/spruce/releases).
```
$ brew tap starkandwayne/cf
$ brew install spruce
```
Cepler can be downloaded as a [pre-built binary](https://github.com/bodymindarts/cepler/releases):
```
$ wget https://github.com/bodymindarts/cepler/releases/download/v0.4.1/cepler-x86_64-apple-darwin-0.4.1.tar.gz
$ tar -xvzf ./cepler-x86_64-apple-darwin-0.4.1.tar.gz
x cepler-x86_64-apple-darwin-0.4.1/
x cepler-x86_64-apple-darwin-0.4.1/cepler
$ mv cepler-x86_64-apple-darwin-0.4.1/cepler <somewhere-on-your-PATH>
```

Or if you have a rust toolchain installed via:
```
$ cargo install cepler
```

Check that everything is installed via:
```
$ cepler --version
cepler 0.4.1
$ spruce --version
spruce - Version 1.27.0
```

## Test deploy

Before introducing cepler lets have a look at what we are deploying.

The following files make up the configuration of our system across all environments:
```
% tree k8s
k8s
├── deployment.yml
└── environments
    ├── production.yml
    ├── shared.yml
    └── staging.yml

1 directory, 4 files
```

The [k8s/deployment.yml](./k8s/deployment.yml) file represents the 'system' we are deploying:
```
$ cat k8s/deployment.yml
meta:
  environment_name: (( param "Please provide meta.environment_name" ))
  image_tag: (( param "Please provide meta.image_tag" ))

  app_name: nginx
  deployment_name: (( concat meta.environment_name "-" meta.app_name "-deployment" ))
  deployment_tags:
    app: (( concat meta.environment_name "-" meta.app_name ))

apiVersion: apps/v1
kind: Deployment
metadata:
  name: (( grab meta.deployment_name ))
spec:
  selector:
    matchLabels: (( grab meta.deployment_tags ))
  replicas: 2
  template:
    metadata:
      labels: (( grab meta.deployment_tags ))
    spec:
      containers:
      - name: (( grab meta.app_name ))
        image: (( concat "nginx:" meta.image_tag ))
        ports:
        - containerPort: 80
```
At the top of the file under the `meta` tag we have deduplicated some settings and also specified some keys that require overriding:
```
$ spruce merge k8s/deployment.yml
2 error(s) detected:
 - $.meta.environment_name: Please provide meta.environment_name
 - $.meta.image_tag: Please provide meta.image_tag
```
The `meta.environment_name` override will be specified via an environment specific input file:
```
$ cat k8s/environments/staging.yml
meta:
  environment_name: staging
```
The `meta.image_tag` setting represents the version of our system that we will want to propagate from environment to environment.
```
$ cat k8s/environments/shared.yml
meta:
  image_tag: "1.18.0"
```

To deploy the `staging` environment we could use the following command:
```
$ spruce merge --prune meta k8s/*.yml k8s/environments/shared.yml k8s/environments/staging.yml | kubectl apply  -f -
deployment.apps/staging-nginx-deployment created
$ kubectl get deployments
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
staging-nginx-deployment   2/2     2            2           4s
```

## Introducing cepler

To let cepler manage the state of the files that are specific to an environment we need to add a `cepler.yml`:
```
$ cat cepler.yml
environments:
  staging:
    latest:
    - k8s/deployment.yml
    - k8s/environments/shared.yml
    - k8s/environments/staging.yml
  production:
    latest:
    - k8s/environments/production.yml
    passed: staging
    propagated:
    - k8s/*.yml
```

As we can see the `cepler.yml` file specifies which files make up an environment and which of those should be vetted in a previous environment.
The `check` command gives us feedback on wether or not files have changed in a way that requires a new deploy:
```
$ cepler check -e staging
File k8s/deployment.yml was added
File k8s/environments/shared.yml was added
File k8s/environments/staging.yml was added
Found new state to deploy - trigger commit f5b1ba0
$ cepler check -e production
Error: Previous environment 'staging' not deployed yet
```
At this point `staging` is ready to deploy but `production` shouldn't be deployed yet since the `propagated` files haven't been vetted yet.
