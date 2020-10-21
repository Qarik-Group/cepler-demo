# Cepler demo

This repository serves as an introduction to the local usage of [cepler](https://github.com/bodymindarts/cepler).

## Introduction

When operating software it is common to have more than 1 deployment of your system running.
These deployments are typically segregated into multiple environments (such as dev / staging / production).
One goal here is to de-risk making changes to the production system where end-users may be effected.
By trying out software upgrades or config changes on a 'non-production' we can environment verify our expectations around the changes we are about to make .

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

To merge them together we will use [spruce](https://github.com/geofffranks/spruce#how-do-i-get-started).

Cepler can be downloaded as a [pre-built binary](https://github.com/bodymindarts/cepler/releases).
Or if you have a rust toolchain installed via:
```
$ cargo install cepler
```

Check that everything is installed via:
```
$ cepler --version
cepler 0.4.5
$ spruce --version
spruce - Version 1.27.0
```

## Test deploy

Before introducing cepler lets have a look at what we are deploying.

The following files make up the configuration of our system across all environments:
```
$ git clone https://github.com/starkandwayne/cepler-demo && cd cepler-demo
$ tree k8s
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
$ git add k8s/environments/shared.yml && git commit -m 'Bump app version'
```

At this point the state of `k8s/environments/shared.yml` is different from what was recorded as the last deployment to `staging`:
```
$ grep 'environments/shared.yml' -A 1 .cepler/staging.state
   "{latest}/k8s/environments/shared.yml":
     file_hash: 23451f22e83b6e8da62c2198ac43142d08f1b8f6
$ git hash-object k8s/environments/shared.yml
dfbaa85e62ce8edc7fc90c9dab106d2e2e4945ec
```

The latest state of the file hasn't been vetted yet (via a deploy to `staging`) so when we `prepare` the production deploy it will check out the last state to pass staging.
```
$ cepler prepare -e production --force-clean
WARNING removing all non-cepler specified files
$ tree
.
├── cepler.yml
└── k8s
    ├── deployment.yml
    └── environments
        ├── production.yml
        └── shared.yml
$ git hash-object k8s/environments/shared.yml
23451f22e83b6e8da62c2198ac43142d08f1b8f6
```

Now that we have prepared the workspace with the files for production we can go ahead and deploy to production:
```
$ spruce merge --prune meta k8s/**/*.yml | kubectl apply  -f -
% kubectl get deployments
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
production-nginx-deployment   2/2     2            2           78s
staging-nginx-deployment      2/2     2            2           19s
```
After deploying we need to record the state for production:
```
$ cepler record -e production
Recording current state
Adding commit to repository to persist state
$ cat .cepler/production.state
---
current:
  head_commit: 09cd76205cc1efed1a975a711f8331ba1ee9f256
  propagated_head: 12d50cd01cf8631fb73a5ddcc52316ccae1b4988
  files:
    "{latest}/k8s/environments/production.yml":
      file_hash: 8d7bae8892cb8e02d318b0829198a2b6d8efdd4e
      from_commit: d2f769d275a2e5808d6f2be6c20d4b6cd1ce3fbe
      message: Move testflight -> production
    "{staging}/k8s/deployment.yml":
      file_hash: d78a37bbd8971a40c49841fe958d6ddb59444c36
      from_commit: f5b1ba0a92be43c038120c6fb2447df98c4df79a
      message: Readme
    "{staging}/k8s/environments/shared.yml":
      file_hash: 23451f22e83b6e8da62c2198ac43142d08f1b8f6
      from_commit: c485204c31b86d81b14ea829bdd2a5f56ac24dd8
      message: Use image tag as shared input
propagated_from: staging%
```

Finally after checking out the head state again lets see what check returns:
```
$ git checkout .
$ cepler check -e production
Nothing new to deploy
$ cepler check -e staging
File k8s/environments/shared.yml changed
Found new state to deploy - trigger commit ad57826
```

As we can see since we just deployed and recorded production there is nothing to do for that environment.
But we haven't yet applied the upgraded version in the `shared.yml` file to staging which is why that check is telling us there is a new state.
Also note that the 'trigger commit' accuratly identifies the last change that was relevent to the state of the environment:

```
% git show ad57826
commit ad578268492be4c520cc108cd210cf526271b7c5
Author: Justin Carter <justin@misthos.io>
Date:   Thu Oct 15 10:44:50 2020 +0200

    Bump app version

diff --git a/k8s/environments/shared.yml b/k8s/environments/shared.yml
index 23451f2..dfbaa85 100644
--- a/k8s/environments/shared.yml
+++ b/k8s/environments/shared.yml
@@ -1,2 +1,2 @@
meta:
-  image_tag: "1.18.0"
+  image_tag: "1.19.0"
```

## Conclusion

In this demonstration we have seen how `cepler` can help you manage configuration files that define how a system should be deployed to multiple environments.

There are 3 basic commands in cepler `check`, `prepare`, `record`.
- `cepler check -e <environment>` - Check if an environment needs deploying
- `cepler prepare -e <environment>` - Prepare the state of the files checked out in the current directory for deployment
- `cepler record -e <environment>` -  Record (and commit) metadata about files currently checked out and relevant to the environment

By using the cycle of:
```
$ cepler check -e <environment>
$ cepler prepare -e <environment>
$ <execute deploy command>
$ cepler record -e <environment>
```
We can ensure an orderly propagation of changes accross environments.

Here we have demonstrated this workflow using the cli commands on our local workstation.
They are also particularly usefull when used within the context of a CI/CD system.
Exploring cepler integration within a tool for workflow automation will be the subject of a future post.

You can use the `help` command to explore additional functionality and options:
```
% cepler help
cepler 0.4.5

USAGE:
    cepler [OPTIONS] <SUBCOMMAND>

FLAGS:
    -h, --help       Prints help information
    -V, --version    Prints version information

OPTIONS:
        --clone <CLONE_DIR>                    Clone the repository into <dir>
    -c, --config <CONFIG_FILE>                 Cepler config file [env: CEPLER_CONF=]  [default: cepler.yml]
        --git-branch <GIT_BRANCH>              Branch for --clone option [env: GIT_BRANCH=]  [default: main]
        --git-private-key <GIT_PRIVATE_KEY>    Private key for --clone option [env: GIT_PRIVATE_KEY=]
        --git-url <GIT_URL>                    Remote url for --clone option [env: GIT_URL=]

SUBCOMMANDS:
    check        Check wether the environment needs deploying. Exit codes: 0 - needs deploying; 1 - internal error;
                 2 - nothing to deploy
    concourse    Subcommand for concourse integration
    help         Prints this message or the help of the given subcommand(s)
    ls           List all files relevent to a given environment
    prepare      Prepare workspace for hook execution
    record       Record the state of an environment in the statefile
```
