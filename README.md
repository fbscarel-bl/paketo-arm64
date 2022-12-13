# Paketo Buildpacks Multi-Architecture Builder

This repo is used to generate:
- `dashaun/builder-arm:tiny` a modified version of `paketobuildpacks/builder:tiny` that works with ARM64 like M1, M2, and Raspberry Pi
- `dashaun/builder:tiny` a manifest delivering `dashaun/builder-arm:tiny` for ARM64 and `paketobuildpacks/builder:tiny` for AMD64

## Quick Start

Create a Spring Boot project:
```bash
curl https://start.spring.io/starter.tgz -d dependencies=web,actuator,native -d javaVersion=17 -d bootVersion=3.0.0 -d type=maven-project | tar -xzf -
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

## Goals of this repository

- Deliver a buildpack that can be used for ARM64
- Deliver a buildpack that can be used the same way on ARM64 and AMD64
- Help deliver ARM64 and multi-architecture support upstream to [Paketo](https://paketo.io)

Please use it and provide feedback!

Pull requests are welcome!

## Details on the Automation Scripts

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
