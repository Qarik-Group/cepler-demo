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
