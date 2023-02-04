[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]

# Paketo Buildpacks Multi-Architecture Builder

[![dashaun/builder-arm](https://github.com/dashaun/paketo-arm64/actions/workflows/paketo-arm64.yml/badge.svg)](https://github.com/dashaun/paketo-arm64/actions/workflows/paketo-arm64.yml) | [![dashaun/builder](https://github.com/dashaun/paketo-arm64/actions/workflows/create-manifest.yml/badge.svg)](https://github.com/dashaun/paketo-arm64/actions/workflows/create-manifest.yml) | [![dashaun/jammy](https://github.com/dashaun/paketo-arm64/actions/workflows/create-stacks.yml/badge.svg)](https://github.com/dashaun/paketo-arm64/actions/workflows/create-stacks.yml)

This repo is used to generate:
- [dashaun/builder-arm](https://hub.docker.com/r/dashaun/builder-arm) a modified version of `paketobuildpacks/builder` that works with ARM64 architectures like M1, M2, and Raspberry Pi
- [dashaun/builder](https://hub.docker.com/r/dashaun/builder) a manifest delivering `dashaun/builder-arm:tiny` for ARM64 and `paketobuildpacks/builder:tiny` for AMD64

## Issues & Support



## Quick Start

Create a Spring Boot project:
```bash
curl https://start.spring.io/starter.tgz -d dependencies=web,actuator,native -d javaVersion=17 -d bootVersion=3.0.2 -d type=maven-project | tar -xzf -
```

In the pom.xml replace this:
```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
        </plugin>
    </plugins>
</build>
```

with this:

```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
            <configuration>
                <image>
                    <builder>dashaun/builder:tiny</builder>
                </image>
            </configuration>
        </plugin>
    </plugins>
</build>
```

Create OCI images just like you would with `paketobuildpacks/builder:tiny`:
```bash
./mvnw -Pnative spring-boot:build-image
```

Test the image by running it with docker:
```bash
docker run --rm -d -p 8080:8080 demo:0.0.1-SNAPSHOT
```

Validate the image:
```bash
http :8080/actuator/health
```
```text
HTTP/1.1 200 
Connection: keep-alive
Content-Type: application/vnd.spring-boot.actuator.v3+json
Date: Sat, 04 Feb 2023 05:04:36 GMT
Keep-Alive: timeout=60
Transfer-Encoding: chunked

{
    "status": "UP"
}
```

## Goals of this repository

- Deliver a buildpack that can be used with `Spring Boot 3` and `GraalVM` on ARM64 architecture
- Deliver a buildpack that can be used the same way on ARM64 and AMD64
- Help deliver ARM64 and multi-architecture support upstream to [Paketo](https://paketo.io)

Please use it and provide feedback! Pull requests are welcome!

## Automation Scripts

1. [tiny.sh](https://github.com/dashaun/paketo-arm64/blob/main/scripts/tiny.sh) creates a multi-architecture version of [builder:tiny](https://github.com/paketo-buildpacks/tiny-builder) but uses `Ubuntu Jammy` instead of `Ubuntu Bionic`

(more builders coming)

## GitHub Action Workflow

[ARM64 Self Hosted GitHub Action Runner](https://github.com/dashaun/tf-oci-arm) - Terraform to configure ARM64 VM in Oracle Cloud

## See Also

- [Forked from dmikusa/paketo-arm64](https://github.com/dmikusa/paketo-arm64)
- [Blog](https://dashaun.com)

## Thank you

- [Daniel Mikusa](https://twitter.com/dmikusa)
- [Salman Malik](https://twitter.com/SalmanTheMalik)

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[forks-shield]: https://img.shields.io/github/forks/dashaun/paketo-arm64.svg?style=for-the-badge
[forks-url]: https://github.com/dashaun/paketo-arm64/network/members
[stars-shield]: https://img.shields.io/github/stars/dashaun/paketo-arm64.svg?style=for-the-badge
[stars-url]: https://github.com/dashaun/paketo-arm64/stargazers
[issues-shield]: https://img.shields.io/github/issues/dashaun/paketo-arm64.svg?style=for-the-badge
[issues-url]: https://github.com/dashaun/paketo-arm64/issues
