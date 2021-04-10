---
title: "Hugo with docker and automatic deployment"
date: 2021-04-10T13:17:49+12:00
---

Hello! 你好！Kia Ora! This is the first post of this blog, so I might just 
write down how I made this website from scratch. 

I run a server at home with couples of utility websites on it, using
docker-compose with [traefik](https://traefik.io/). 

The goals of this blog are simple:

* The blog will be self-hosted using docker
* The blog posts will be written in markdown
* Data loss should be **easily** avoided
* Changes should be deployed automatically

The solution I come up with:
* Hugo as the content generator
* Hugo project hosted on Gitlab
* Upon push, Gitlab CI will deploy the website into a Docker image
* [watchtower](https://github.com/containrrr/watchtower) automatically updates the
  website's docker image and restart the container.

The advantages of writing blog this way:
* No maintenance needed. All the content is on Gitlab, and I trust Gitlab to be 
  competent.
* Markdown is great. Standard, easy and clean to read even without being rendered,
  No more writing HTML.
  
I have a few notes along the way when working this out:

### Using multi-staged Dockerfile to build a slim image

When running `docker build`, it will pull down the `hugo` image and run hugo commands
to generate the website. However, because the website is all static, once generated,
`hugo` is no longer necessary. We just need the `nginx` to serve the static files.

<!--more-->

So we split the docker build process into two phases, like this:

```Dockerfile
FROM jojomi/hugo

WORKDIR /app
COPY . ./

ENV TZ=Pacific/Auckland
RUN apk add tzdata && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN hugo -d /out --minify

FROM nginx:alpine
COPY --from=0 /out /usr/share/nginx/html
```

Now the final image will only include "nginx + your website".

> You probably notice that I have gone into length to make the timezone works.
> This is important because if hugo doesn't know which timezone you are in,
> the default rendering of time will be soulless like "2021-04-10 13:25:22 +1200 +1200".
> Once I set my timezone correctly, it becomes "2021-04-10 13:25:22 +1200 NZST" 😏


### Use Gitlab CI to build and push docker image into Gitlab Container Registry

Gitlab is generous to provide a free CI and Docker container registry. So let's make
it counts.

```yml
image: docker:stable
services:
  - docker:dind

stages:
  - build
  - deploy

before_script:
  - docker login -u gitlab-ci-token -p $CI_JOB_TOKEN $CI_REGISTRY

build:
  stage: build
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .

push:
  stage: deploy
  only:
    - master
  script:
    - docker build -t $CI_REGISTRY_IMAGE:latest .
    - docker push $CI_REGISTRY_IMAGE:latest
```

This is a very nice pipeline that can be used across to other docker building projects.

You have these nice features:

1. Every push will be built, the building processing acts like a pre-push test. You should
   probably add your test process inside `Dockerfile` to make it test all your code

2. Only changes to master triggers the push to docker registry. This will have the
   `latest` docker image tag updated and pushed. This works nicely with common git workflows.
   
3. The pre-defined Gitlab CI variables means you don't need to do anything else to set up 
   the credentials to push the images.
   
### Make `watchtower` play nice with docker compose

Once we have a docker image, we will add them into the docker-compose file with traefik,
so traefik can find it.

```yml
services:
  traefik:
    image: traefik
  ...

  blog:
    image: registry.gitlab.com/xxx/xxx
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
      ...
  
  watchtower:
    image: v2tec/watchtower
    command: --cleanup --label-enable
    restart: always
    environment:
      - WATCHTOWER_POLL_INTERVAL=120
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

The idea here is to make sure watchtower only updates the `blog` container. To
do that, you need `--label-enable` command on watchtower's container, and 
`com.centurylinklabs.watchtower.enable=true` on the container you will to 
auto-update.