FROM jojomi/hugo

WORKDIR /app
COPY . ./

RUN hugo -d /out --minify

FROM nginx:alpine
COPY --from=0 /out /usr/share/nginx/html