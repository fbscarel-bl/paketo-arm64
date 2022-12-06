# Paketo Buildpacks ARM64 Build Instructions

## Prerequisites

1. Get yourself some ARM64 hardware (Mac M1) or a VM (Oracle Cloud has free ARM64 VMs)
2. Install some basic packages: make, curl, git, jq
3. Install Go version 1.17+. Follow instructions [here](https://go.dev/doc/install).
   If building on a Raspberry PI, the version of `golang` included with RaspiOS package manager does not work.
4. This is used later to package buildpacks: `go install github.com/paketo-buildpacks/libpak/cmd/create-package@v1.60.1`.
5. Install `yj` which is used by some of the helper scripts. run `go install github.com/sclevine/yj/v5@v5.1.0`.
6. Add `~/go/bin` to `$PATH`.  Run `export $PATH=$PATH:$HOME/go/bin`.
7. Install Docker.

   - For Mac, you can use Docker Desktop if you meet the criteria of their free-use license restrictions or you pay for a license but you can also use [Colima](https://github.com/abiosoft/colima), [Podman](https://podman.io/getting-started/installation#macos) or Kubernetes installations like Minikube that expose the Docker Daemon directly.
   - For Linux, follow [the instructions here](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository).
   - When done, run `docker pull ubuntu:latest` (or some other image) just to confirm Docker is working.
8. Install the `pack` CLI. There are MacOS & Linux arm64 builds on the project's [Github releases](https://github.com/buildpacks/pack/releases). Download and copy to `/usr/local/bin`.
9. Grab the scripts used in this article. `git clone https://github.com/dmikusa-pivotal/paketo-arm64`.

## Create a Stack

Basically [follow the stack creation instructions here](https://buildpacks.io/docs/operator-guide/create-a-stack/).

The instructions below are customized to use `ubuntu:focal` as the base image. You can use other base images, but you need to ensure there is a compatile ARM64 image available. For example, you cannot use `paketobuildpacks/build` or `paketobuildpacks/run` because these do not have ARM64 images at the moment. When Paketo is publishing ARM64 images for it's build/run images, you can skip this step and use them directly.

In the meantime:

1. Get a base image, `sudo docker pull ubuntu:focal`
2. `cd paketo-arm64/stack`
3. Customize the `Dockerfile`

You can customize the creation of the image in any way you need, for example if you need to add additional packages or tools to the build or run images. Just be aware that with the run image, whatever you add will end up in the final images used by application images you build.

When you're ready, build the images:

1. Build the run image: `sudo docker build . -t dmikusa2pivotal/stack-run:focal --target run --build-arg STACK_ID="<your-stack-id>"`
2. Build the build image: `sudo docker build . -t dmikusa2pivotal/stack-build:focal --target build --build-arg STACK_ID="<your-stack-id>"`

Your stack id can be anything, it just needs to be consistent across both images, and you also need to pass the value into the script when you create the builder below.

Congrats! You now have stack images.

## Package your Buildpacks

Next we need to build and package all of the buildpacks, with a few modifications. This is a tedious process, so I'm including some scripts to make it easier. There is still a little bit of manual work required, but it's a lot simpler with the scripts.

Here's the general process that is mostly automated by the scripts:

1. Clone and checkout all of the buildpacks we need.
2. Update buildpack.toml and package.toml to have unique ids [1].
3. Update any dependencies that are architecture specific to reference arm64 downloads. For Java, this is fortunately a small list: bellsoft-liberica, syft, and watchexec. [2]
4. Build the buildpacks. This includes the changes above and compiles arm64 binaries for build and detect.
5. Package the buildpacks into arm64 images.

[1] The current suite of packaging tools do not support manifest images, so you need to tag your images as `-arm64` or something to differenitate them from the standard buildpack images which are x86.
[2] This is a manual step.

Here are updated buildpack.toml files at the time of writing. You will need to manually check if there are newer versions of dependencies and update the buildpack.toml entries accordingly to ensure you have the latest dependencies.

1. [bellsoft-liberica](https://github.com/dmikusa-pivotal/paketo-arm64/blob/main/arm64-toml/bellsoft.toml)
2. [syft](https://github.com/dmikusa-pivotal/paketo-arm64/blob/main/syft.toml)
3. [watchexec](https://github.com/dmikusa-pivotal/paketo-arm64/blob/main/watchexec.toml)

The means the steps to execute are as follows:

1. `./scripts/clone.sh <buildpack-id> <buildpack-version>`
2. `find ./buildpacks  -name "buildpack.toml" | xargs -n 1 ./scripts/mod-bptoml.sh`
3. `find ./buildpacks  -name "package.toml" | xargs -n 1 ./scripts/mod-pkgtoml.sh`
4. Copy the `buildpack.toml` files for the three buildpacks referenced above from `paketo-arm64/arm64-toml`. Overwrite the `buildpack.toml` file in the project folder under the working directory with each. [1]
5. `./scripts/build.sh <buildpack-id>`

[1] This example works for `paketo-buildpacks/java` and will require three modified `buildpack.toml` files. You may not need all three if you use a different composite buildpack, like `paketo-buildpacks/java-native-image` which only requires bellsoft and syft. Other composite buildpacks may require more modifications, it depends native code gets installed by that suite of buildpacks.

At this point, you should have images. Run `docker images` to see what's there.

If you want to start over run `./scripts/reset.sh <buildpack-id> <buildpack-version>` or re-run the first step. The reset script will be slightly faster as it doesn't need to redownload everything.

## Create a Builder

Once you have buildpack images, it's time to build an builder image. There is a script for this as well. It'll generate a `builder.toml` file based on some input information and run `pack create builder` on that.

Run `create-builder.sh <buildpack-id> <buildpack-version> <lifecycle-version> <run-img> <build-img> <stack-id> <builder-id>`

The required information is as follows:

- The composite buildpack id
- The composite buildpack version
- A lifecycle version to use, whatever is latest often works best
- Your custom run image from above
- Your custom build build image from above
- The stack id you used when creating the stack above
- The name of your builder image

Here are a couple of examples:

- For `paketo-buildpacks/java` -> `./scripts/create-builder.sh paketo-buildpacks/java 6.4.0 0.14.0 docker.io/dmikusa2pivotal/stack-run:focal docker.io/dmikusa2pivotal/stack-build:focal com.mikusa.stacks.focal dmikusa2pivotal/builder:focal`
- For `paketo-buildpacks/java-native-image` -> `./scripts/create-builder.sh paketo-buildpacks/java-native-image 7.4.0 0.14.0 docker.io/dmikusa2pivotal/stack-run:focal docker.io/dmikusa2pivotal/stack-build:focal com.mikusa.stacks.focal dmikusa2pivotal/native-builder:focal`
- For `paketo-community/rust` -> `./scripts/create-builder.sh paketo-community/rust 0.10.0 0.14.0 docker.io/dmikusa2pivotal/rust-stack-run:focal docker.io/dmikusa2pivotal/rust-stack-build:focal com.mikusa.stacks.focal dmikusa2pivotal/rust-builder:focal`

At this point, you should have a builder with all of your buildpacks. Time to build some apps!

## Build Samples

1. `git clone https://github.com/paketo-buildpacks/samples`
2. Install Java
3. `cd samples/java/maven`
4. `./mvnw package`
5. `sudo ~/pack/out/pack build apps/maven -p target/demo-0.0.1-SNAPSHOT.jar -B docker.io/dmikusa2pivotal/builder:focal --trust-builder`

It should now build & package up the app as an image.

## Troubleshooting

- `pack` not found. This can happen if you modify `$PATH` as some scripts use `sudo` but `sudo` won't inherit your custom `$PATH` by default. It's easier to put the required binaries into the `/usr/local/bin` directory or symlink them.

- If `create-builder.sh` fails, look at `buildpacks/builder/builder.toml`. This is the file that is generated. Review the input data to make sure you've entered the proper information. Often when it fails, it's because the information is not consistent across the buildpacks and builder metadata.

- There may be some issues running on Mac OS. This was tested on ARM64 Linux. For example, the script assumes you need to `sudo` when interacting with the Docker Daemon, which is not true on Mac OS. Open an issue or submit a PR if anything comes up.

## Details on the Automation Scripts

Here is a breakdown of the scripts that you can use to mostly automate this process. If you just want to build, you can probably skip this section. It just provides more information for those that are curious.

1. [clone.sh](https://github.com/dmikusa-pivotal/paketo-arm64/blob/main/scripts/clone.sh) can be used to quickly clone all of the buildpack repositories. It requires the buildpack id and version of a composite buildpack (buildpack that references other buildpacks). It will then go and clone all of the component (referenced buildpacks) and check out the version of those buildpacks set in the composite buildpack.

   For example: `./clone.sh paketo-buildpacks/java 6.4.0`. Will clone all of the referenced component buildpacks & the composite buildpack to the working directory (`./buildpacks`).

2. [mod-bptoml.sh](https://github.com/dmikusa-pivotal/paketo-arm64/blob/main/scripts/mod-bptoml.sh) can be used to quickly change the buildpack id of all the buildpacks. It will go through and append `-arm64` to the end of each buildpack id. This is useful so that there is something to differentiate between the images you're creating and standard x86 images.

   For example: `find ./buildpacks  -name "buildpack.toml" | xargs -n 1 ./mod-bptoml.sh`. This will find all of the buildpack.toml files in the working directory and update them.

3. [mod-pkgtoml.sh](https://github.com/dmikusa-pivotal/paketo-arm64/blob/main/scripts/mod-pkgtoml.sh) can be used to quickly change the image name of all the buildpacks. It will go through and append `-arm64` to the end of each image name. This is useful so that there is something to differentiate between the images you're creating and standard x86 images.

   For example: `find ./buildpacks  -name "buildpack.toml" | xargs -n 1 ./mod-bptoml.sh`. This will find all of the buildpack.toml files in the working directory and update them.

4. [build.sh](https://github.com/dmikusa-pivotal/paketo-arm64/blob/main/scripts/build.sh) can be used to iterate over all of the buildpacks in the working directory (created by `clone.sh`).

   For example: `./build.sh paketo-buildpacks/java`.

5. [reset.sh](https://github.com/dmikusa-pivotal/paketo-arm64/blob/main/scripts/reset.sh) can be used to reset the temporary directory to a given working state. You pass it the composite buildpack id and version. It will reset, pull and check out that version. Then recursively do the same for all referenced buildpacks.

   For example: `./reset.sh paketo-buildpacks/java 6.4.0`. This will reset the working directory to the 6.4.0 version. If this fails, like if new buildpacks have been introduced, then you should run `clone.sh` instead. Running `clone.sh` is similar but wipes and results in a fresh working directory.

6. [create-builder.sh](https://github.com/dmikusa-pivotal/paketo-arm64/blob/main/create-builder.sh) can be used to generate a `builder.toml` and create a builder image. This works by generating a builder.toml based on the information passed into it and what's in the referenced composite buildpack's `buildpack.toml` file. This requires a lot of input so see [this section](#create-a-builder) for details on running it.

## Updating to new versions - manual process

1. For each file in `arm64-toml`
   1. Pull the latest version of the buildpack.toml
   2. Do a diff and update the dependencies and the SHA values for ARM64/aarch64 versions
      1. `shasum -a 256 filename`

2. Update `.github/workflows/paketo-arm64` versions for builder and lifecycle

## pack build inspect

```text

Description: An ARM64 builder based on paketo-buildpacks/java

Created By:
  Name: Pack CLI
  Version: 0.27.0+git-f4f5be1.build-3382

Trusted: No

Stack:
  ID: io.dashaun.stack.focal.arm64

Lifecycle:
  Version: 0.15.0
  Buildpack APIs:
    Deprecated: (none)
    Supported: 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9
  Platform APIs:
    Deprecated: (none)
    Supported: 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.10

Run Images:
  dashaun/stack-run:focal

Buildpacks:
  ID                                                        NAME                                                   VERSION        HOMEPAGE
  paketo-buildpacks/apache-tomcat-arm64                     Paketo Buildpack for Apache Tomcat                     7.8.0          https://github.com/paketo-buildpacks/apache-tomcat
  paketo-buildpacks/apache-tomee-arm64                      Paketo Buildpack for Apache Tomee                      1.3.0          https://github.com/paketo-buildpacks/apache-tomee
  paketo-buildpacks/azure-application-insights-arm64        Paketo Buildpack for Azure Application Insights        5.9.0          https://github.com/paketo-buildpacks/azure-application-insights
  paketo-buildpacks/bellsoft-liberica-arm64                 Paketo Buildpack for BellSoft Liberica                 9.10.0         https://github.com/paketo-buildpacks/bellsoft-liberica
  paketo-buildpacks/ca-certificates-arm64                   Paketo Buildpack for CA Certificates                   3.4.0          https://github.com/paketo-buildpacks/ca-certificates
  paketo-buildpacks/clojure-tools-arm64                     Paketo Buildpack for Clojure Tools                     2.5.0          https://github.com/paketo-buildpacks/clojure-tools
  paketo-buildpacks/datadog-arm64                           Paketo Buildpack for Datadog                           2.5.0          https://github.com/paketo-buildpacks/datadog
  paketo-buildpacks/dist-zip-arm64                          Paketo Buildpack for DistZip                           5.4.0          https://github.com/paketo-buildpacks/dist-zip
  paketo-buildpacks/encrypt-at-rest-arm64                   Paketo Encrypt-at-Rest Buildpack                       4.2.1          https://github.com/paketo-buildpacks/encrypt-at-rest
  paketo-buildpacks/environment-variables-arm64             Paketo Buildpack for Environment Variables             4.3.0          https://github.com/paketo-buildpacks/environment-variables
  paketo-buildpacks/executable-jar-arm64                    Paketo Buildpack for Executable JAR                    6.5.0          https://github.com/paketo-buildpacks/executable-jar
  paketo-buildpacks/google-stackdriver-arm64                Paketo Buildpack for Google Stackdriver                6.7.0          https://github.com/paketo-buildpacks/google-stackdriver
  paketo-buildpacks/gradle-arm64                            Paketo Buildpack for Gradle                            6.8.0          https://github.com/paketo-buildpacks/gradle
  paketo-buildpacks/image-labels-arm64                      Paketo Buildpack for Image Labels                      4.3.0          https://github.com/paketo-buildpacks/image-labels
  paketo-buildpacks/jattach-arm64                           Paketo Buildpack for JAttach                           1.2.0          https://github.com/paketo-buildpacks/jattach
  paketo-buildpacks/java-memory-assistant-arm64             Paketo Java Memory Assistant Buildpack                 1.1.0          https://github.com/paketo-buildpacks/java-memory-assistant
  paketo-buildpacks/leiningen-arm64                         Paketo Buildpack for Leiningen                         4.4.0          https://github.com/paketo-buildpacks/leiningen
  paketo-buildpacks/liberty-arm64                           Paketo Buildpack for Liberty                           2.4.0          https://github.com/paketo-buildpacks/liberty
  paketo-buildpacks/maven-arm64                             Paketo Buildpack for Maven                             6.11.0         https://github.com/paketo-buildpacks/maven
  paketo-buildpacks/procfile-arm64                          Paketo Buildpack for Procfile                          5.4.0          https://github.com/paketo-buildpacks/procfile
  paketo-buildpacks/sbt-arm64                               Paketo Buildpack for SBT                               6.8.0          https://github.com/paketo-buildpacks/sbt
  paketo-buildpacks/spring-boot-arm64                       Paketo Buildpack for Spring Boot                       5.20.0         https://github.com/paketo-buildpacks/spring-boot
  paketo-buildpacks/syft-arm64                              Paketo Buildpack for Syft                              1.22.0         https://github.com/paketo-buildpacks/syft
  paketo-buildpacks/watchexec-arm64                         Paketo Buildpack for Watchexec                         2.7.0          https://github.com/paketo-buildpacks/watchexec

Detection Order:
 └ Group #1:
    ├ paketo-buildpacks/ca-certificates-arm64@3.4.0               (optional)
    ├ paketo-buildpacks/bellsoft-liberica-arm64@9.10.0
    ├ paketo-buildpacks/syft-arm64@1.22.0                         (optional)
    ├ paketo-buildpacks/leiningen-arm64@4.4.0                     (optional)
    ├ paketo-buildpacks/clojure-tools-arm64@2.5.0                 (optional)
    ├ paketo-buildpacks/gradle-arm64@6.8.0                        (optional)
    ├ paketo-buildpacks/maven-arm64@6.11.0                        (optional)
    ├ paketo-buildpacks/sbt-arm64@6.8.0                           (optional)
    ├ paketo-buildpacks/watchexec-arm64@2.7.0                     (optional)
    ├ paketo-buildpacks/executable-jar-arm64@6.5.0                (optional)
    ├ paketo-buildpacks/apache-tomcat-arm64@7.8.0                 (optional)
    ├ paketo-buildpacks/apache-tomee-arm64@1.3.0                  (optional)
    ├ paketo-buildpacks/liberty-arm64@2.4.0                       (optional)
    ├ paketo-buildpacks/dist-zip-arm64@5.4.0                      (optional)
    ├ paketo-buildpacks/spring-boot-arm64@5.20.0                  (optional)
    ├ paketo-buildpacks/procfile-arm64@5.4.0                      (optional)
    ├ paketo-buildpacks/jattach-arm64@1.2.0                       (optional)
    ├ paketo-buildpacks/azure-application-insights-arm64@5.9.0    (optional)
    ├ paketo-buildpacks/google-stackdriver-arm64@6.7.0            (optional)
    ├ paketo-buildpacks/datadog-arm64@2.5.0                       (optional)
    ├ paketo-buildpacks/java-memory-assistant-arm64@1.1.0         (optional)
    ├ paketo-buildpacks/encrypt-at-rest-arm64@4.2.1               (optional)
    ├ paketo-buildpacks/environment-variables-arm64@4.3.0         (optional)
    └ paketo-buildpacks/image-labels-arm64@4.3.0                  (optional)
```

## pack build inspect `native`

```text
Inspecting builder: dashaun/java-native-builder-arm64

REMOTE:

Description: An ARM64 builder based on paketo-buildpacks/java-native-image

Created By:
  Name: Pack CLI
  Version: 0.27.0+git-f4f5be1.build-3382

Trusted: No

Stack:
  ID: io.dashaun.stack.focal.arm64

Lifecycle:
  Version: 0.15.0
  Buildpack APIs:
    Deprecated: (none)
    Supported: 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9
  Platform APIs:
    Deprecated: (none)
    Supported: 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.10

Run Images:
  dashaun/stack-run:focal

Buildpacks:
  ID                                                   NAME                                              VERSION        HOMEPAGE
  paketo-buildpacks/bellsoft-liberica-arm64            Paketo Buildpack for BellSoft Liberica            9.10.0         https://github.com/paketo-buildpacks/bellsoft-liberica
  paketo-buildpacks/ca-certificates-arm64              Paketo Buildpack for CA Certificates              3.4.0          https://github.com/paketo-buildpacks/ca-certificates
  paketo-buildpacks/environment-variables-arm64        Paketo Buildpack for Environment Variables        4.3.0          https://github.com/paketo-buildpacks/environment-variables
  paketo-buildpacks/executable-jar-arm64               Paketo Buildpack for Executable JAR               6.5.0          https://github.com/paketo-buildpacks/executable-jar
  paketo-buildpacks/gradle-arm64                       Paketo Buildpack for Gradle                       6.8.0          https://github.com/paketo-buildpacks/gradle
  paketo-buildpacks/image-labels-arm64                 Paketo Buildpack for Image Labels                 4.3.0          https://github.com/paketo-buildpacks/image-labels
  paketo-buildpacks/leiningen-arm64                    Paketo Buildpack for Leiningen                    4.4.0          https://github.com/paketo-buildpacks/leiningen
  paketo-buildpacks/maven-arm64                        Paketo Buildpack for Maven                        6.11.0         https://github.com/paketo-buildpacks/maven
  paketo-buildpacks/native-image-arm64                 Paketo Buildpack for Native Image                 5.6.0          https://github.com/paketo-buildpacks/native-image
  paketo-buildpacks/procfile-arm64                     Paketo Buildpack for Procfile                     5.4.0          https://github.com/paketo-buildpacks/procfile
  paketo-buildpacks/sbt-arm64                          Paketo Buildpack for SBT                          6.8.0          https://github.com/paketo-buildpacks/sbt
  paketo-buildpacks/spring-boot-arm64                  Paketo Buildpack for Spring Boot                  5.20.0         https://github.com/paketo-buildpacks/spring-boot
  paketo-buildpacks/syft-arm64                         Paketo Buildpack for Syft                         1.22.0         https://github.com/paketo-buildpacks/syft
  paketo-buildpacks/upx-arm64                          Paketo Buildpack for UPX                          3.3.0          https://github.com/paketo-buildpacks/upx

Detection Order:
 └ Group #1:
    ├ paketo-buildpacks/ca-certificates-arm64@3.4.0          (optional)
    ├ paketo-buildpacks/upx-arm64@3.3.0                      (optional)
    ├ paketo-buildpacks/bellsoft-liberica-arm64@9.10.0
    ├ paketo-buildpacks/syft-arm64@1.22.0                    (optional)
    ├ paketo-buildpacks/leiningen-arm64@4.4.0                (optional)
    ├ paketo-buildpacks/gradle-arm64@6.8.0                   (optional)
    ├ paketo-buildpacks/maven-arm64@6.11.0                   (optional)
    ├ paketo-buildpacks/sbt-arm64@6.8.0                      (optional)
    ├ paketo-buildpacks/executable-jar-arm64@6.5.0           (optional)
    ├ paketo-buildpacks/spring-boot-arm64@5.20.0             (optional)
    ├ paketo-buildpacks/native-image-arm64@5.6.0
    ├ paketo-buildpacks/procfile-arm64@5.4.0                 (optional)
    ├ paketo-buildpacks/environment-variables-arm64@4.3.0    (optional)
    └ paketo-buildpacks/image-labels-arm64@4.3.0             (optional)
```

## Docker manifest inspect `native`

```text
{
        "Ref": "docker.io/dashaun/java-native-builder-arm64:latest",
        "Descriptor": {
                "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
                "digest": "sha256:80771c9c2efee25020ba60e320c41cc385a333434ad2982ed7326a0a413b9ae7",
                "size": 5150,
                "platform": {
                        "architecture": "arm64",
                        "os": "linux"
                }
        },
        "SchemaV2Manifest": {
                "schemaVersion": 2,
                "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
                "config": {
                        "mediaType": "application/vnd.docker.container.image.v1+json",
                        "size": 12587,
                        "digest": "sha256:8cd1ead83689b853055ac2de0cc07c5f3c9d8d087b2ac97e838551fe8e962e00"
                },
                "layers": [
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 27195998,
                                "digest": "sha256:4e7e0215f4adc2c48ad9cb3b3781e21d474b477587f85682c2e2975ae91dce9d"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 4348,
                                "digest": "sha256:fc2e670f062f6edbb1b3be6aae88cbc0978a5273314c365bc4e99d861dfb5ff1"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 103281689,
                                "digest": "sha256:cba3892e6fcca4b47983803d53b777bc05476639fcfc1a2d4f384eac40363677"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 179,
                                "digest": "sha256:f5230b5f167cfc41fb9f96d53de0d9c5832e3b03e3a705052cf42ceada13aea9"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 197,
                                "digest": "sha256:357fefdf9bc907107a38600cf8d79c713346dc97370273d1aa79635d97a2f6f9"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 8870380,
                                "digest": "sha256:0ab7ccc1e1a42589b53d1397672009a979b296933efc276d79d3a2cdc336656c"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 2498256,
                                "digest": "sha256:fa161ac7a0015773c3f6890d6f1824957a6e21cee5a9bbf8ddc60e4e6d30a3ed"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 1806073,
                                "digest": "sha256:bdfdd20caee6a7044607d11d9a4f758a007ad2d61399ea5e3db22a7037ab4975"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 3273385,
                                "digest": "sha256:bc251569386a8e5fd513c85d9c51e76a258f0e59d0f945e185e101930012c9db"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 1509592,
                                "digest": "sha256:caeca36964d2da6c2b88abd998281e4fd5b708cfdd1440486f6acf7bc569292e"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 3191207,
                                "digest": "sha256:f840d9ee444653d04a2181d1d99e4f579d01b56349cce9325c6dade9af410998"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 3273637,
                                "digest": "sha256:b4f56cede28073295dc750e93678876a55b9fdafd97c940b97dc9a01ae345663"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 2387292,
                                "digest": "sha256:cebaf5f7c6e3350f5973f2c77f9ba90138d5a6bb2f1eb9e86084c8cf9f6117c6"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 4208510,
                                "digest": "sha256:47be0bf349071cb594970ef2d18f383b91231645ba49f27b5b39b47d9090aedc"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 1818619,
                                "digest": "sha256:5844db3d59f2bdc13aa19a6fd09789cf4a12aa87088759840a79c10eb01f93c5"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 1569855,
                                "digest": "sha256:89975d6b7daf9b8cf8b1a8350461e9e009b0ffc2a482becb9e1073adc3475153"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 2413551,
                                "digest": "sha256:aca3b8db4220fa7d69bf9cbd0bebc048cfa381174929828affb820c5b6b0f505"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 2480839,
                                "digest": "sha256:71bd4e702bfc97f1db60e6a5ac364897b2818dc2f92f1bf9d78c2935a1ae125d"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 2521983,
                                "digest": "sha256:3e1f506f69017dbcedb2a2b022ff0d6e63d4c0cd44e32fdcf6cc9e39b2416ade"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 2475996,
                                "digest": "sha256:f617bf8af0912672e16ed61332d6e7ad1f0ffc4fffe049da45ea670a1c441afd"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 362,
                                "digest": "sha256:0e3fabdd36281c4c1c946d09854510dc82ffd61476d62aaa474b3c64d8969ae3"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 151,
                                "digest": "sha256:9602e7831cd64261f173d4789e26f9cada67107ba1688409f7781bd737792b58"
                        },
                        {
                                "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                "size": 32,
                                "digest": "sha256:4f4fb700ef54461cfa02571ae0db9a0dc1e0cdb5577484a6d75e68dc38e8acc1"
                        }
                ]
        }
}
```

## Building the multi-arch image

```text
docker manifest create \
dashaun/java-native-builder-multiarch:7.37.0 \
--amend dashaun/java-native-builder-arm64:7.37.0 \
--amend paketo-buildpacks/java-native-image
```