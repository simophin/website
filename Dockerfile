FROM jojomi/hugo

WORKDIR /app
COPY . ./

ENV TZ=Pacific/Auckland
RUN apk add tzdata && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN hugo -d /out --minify

FROM nginx:alpine
COPY --from=0 /out /usr/share/nginx/html