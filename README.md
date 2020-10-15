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
$ wget https://github.com/bodymindarts/cepler/releases/download/v0.4.2/cepler-x86_64-apple-darwin-0.4.2.tar.gz
$ tar -xvzf ./cepler-x86_64-apple-darwin-0.4.2.tar.gz
x cepler-x86_64-apple-darwin-0.4.2/
x cepler-x86_64-apple-darwin-0.4.2/cepler
$ mv cepler-x86_64-apple-darwin-0.4.2/cepler <somewhere-on-your-PATH>
```

Or if you have a rust toolchain installed via:
```
$ cargo install cepler
```

Check that everything is installed via:
```
$ cepler --version
cepler 0.4.2
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
    - k8s/*.yml
    - k8s/environments/shared.yml
    - k8s/environments/staging.yml
  production:
    latest:
    - k8s/environments/production.yml
    passed: staging
    propagated:
    - k8s/*.yml
    - k8s/environments/shared.yml
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

## Deploying an environment

From here on the best way to follow along is on a branch other than `master` to not taint the state.
```
$ git checkout -b demo
```

To prepare for deploying an environment. We use the `prepare` command:
```
$ cepler prepare -e staging
```

In this case the command will be a no-op because for staging all files that are relevant should be checked out to their `latest` commited state (see `cepler.yml` above).
To be sure that no other files accidentally taint the configuration of the environment we are about to deploy we can add the `--force-clean` flag rendering only the files that pass the specified globs.
```
$ cepler prepare -e staging --force-clean
$ tree
.
├── cepler.yml
└── k8s
    ├── deployment.yml
    └── environments
        └── shared.yml
        └── staging.yml
```
Now that we have just the files we want in our workspace we can simplify the deploy command:
```
$ spruce merge --prune meta k8s/**/*.yml | kubectl apply  -f -
```
Once the deploy is complete we want cepler to record the state the files for later reproduction or propagation. The `record` command will persist metadata about the state of the files involved in a deploy into a state file and commit it to the repository.
```
$ cepler record -e staging
Recording current state
Adding commit to repository to persist state
$ cat .cepler/staging.state
---
current:
  head_commit: 12d50cd01cf8631fb73a5ddcc52316ccae1b4988
  files:
    "{latest}/k8s/deployment.yml":
      file_hash: d78a37bbd8971a40c49841fe958d6ddb59444c36
      from_commit: f5b1ba0a92be43c038120c6fb2447df98c4df79a
      message: Readme
    "{latest}/k8s/environments/shared.yml":
      file_hash: 23451f22e83b6e8da62c2198ac43142d08f1b8f6
      from_commit: c485204c31b86d81b14ea829bdd2a5f56ac24dd8
      message: Use image tag as shared input
    "{latest}/k8s/environments/staging.yml":
      file_hash: ab94f97964beadcb829d8a749da7cff05b82d874
      from_commit: 8140c5d28607bcb33fb321acd565a4f542373e81
      message: Initial commit%
```
For each file we have the file hash (can be verified via `git hash-object k8s/deployment.yml`) and the commit hash + message of the last commit that changed the file.

## Propagating changes

At this point we can re-check production and expect that it needs deploying.
```
$ cepler check -e production
File k8s/environments/production.yml was added
File k8s/deployment.yml was added
File k8s/environments/shared.yml was added
Found new state to deploy - trigger commit a12695c
```

But before deploying production lets assume that someone has checked in an later version of the system to be deployed.
```
$ cat <<EOF > k8s/environments/shared.yml
meta:
  image_tag: "1.19.0"
EOF
$ git add k8s/environment/shared.yml && git commit -m 'Bump app version'
```
