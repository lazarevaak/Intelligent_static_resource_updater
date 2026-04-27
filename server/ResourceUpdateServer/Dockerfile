FROM swift:6.0-jammy AS build

WORKDIR /build

COPY Package.swift Package.resolved ./
RUN git config --global http.version HTTP/1.1 \
    && git config --global http.postBuffer 524288000 \
    && git config --global core.compression 0 \
    && swift package resolve

COPY Sources ./Sources
COPY Tests ./Tests
COPY Public ./Public

RUN swift build -c release --product ResourceUpdateServer \
    && mkdir -p /staging \
    && cp "$(swift build -c release --show-bin-path)/ResourceUpdateServer" /staging/ResourceUpdateServer \
    && cp -R Public /staging/Public

FROM swift:6.0-jammy

WORKDIR /app

ENV HOST=0.0.0.0 \
    PORT=8080

COPY --from=build /staging/ResourceUpdateServer /app/ResourceUpdateServer
COPY --from=build /staging/Public /app/Public

EXPOSE 8080

CMD ["/app/ResourceUpdateServer"]
