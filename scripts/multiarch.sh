#!/bin/bash
set -eo pipefail

WORK="./buildpacks"

# Exit if WORK is empty
if [ -z "$WORK" ]; then
    echo "WORK cannot be empty"
    exit 254
fi

# Function to initialize directories and download files
init() {
    mkdir -p "$WORK"
    rm -rf "${WORK:?}/"*

    mkdir -p "$WORK/paketo-buildpacks"
    ln -s "${PWD}/${WORK}/paketo-buildpacks" "${PWD}/${WORK}/dashaun"

    download_file "https://raw.githubusercontent.com/paketo-buildpacks/builder-jammy-buildpackless-tiny/main/builder.toml" "$WORK/builder.toml"

    JAVA_NATIVE_IMAGE_VER=$(extract_version "java-native-image")
    JAVA_VER=$(extract_version "java")
    PROCFILE_VER=$(extract_version "procfile")
    GO_VER=$(extract_version "go")

    pull_docker_images
}

# Function to download a file quietly
download_file() {
    wget -q "$1" -O "$2" >/dev/null 2>&1
}

# Function to extract version from builder.toml
extract_version() {
    grep "docker://gcr.io/paketo-buildpacks/$1:" "$WORK/builder.toml" | cut -d ':' -f 3 | cut -d '"' -f1
}

# Function to pull necessary Docker images
pull_docker_images() {
    docker pull paketobuildpacks/build-jammy-tiny:0.2.3
    docker pull paketobuildpacks/run-jammy-tiny:latest
    docker pull dmikusa/build-jammy-base:0.0.2
    docker pull dmikusa/run-jammy-base:0.0.2

    docker pull gcr.io/paketo-buildpacks/procfile:$PROCFILE_VER
    docker pull gcr.io/paketo-buildpacks/go:$GO_VER
}

# Function to clone and checkout a buildpack
clone_buildpack (){
  BPID="$1"
  BPVER="$2"
  git clone -q "https://github.com/$BPID" "$WORK/$BPID" >/dev/null 2>&1 &&
  pushd "$WORK/$BPID" >/dev/null
  git -c "advice.detachedHead=false" checkout "v$BPVER"
  popd

  for GROUP in $(yj -t < "$WORK/$BPID/buildpack.toml" | jq -rc '.order[].group[]'); do
    BUILDPACK=$(echo "$GROUP" | jq -r ".id")
    VERSION=$(echo "$GROUP" | jq -r ".version")
    if [ ! -d "$WORK/$BUILDPACK" ]; then
      git clone -q --filter=tree:0 "https://github.com/$BUILDPACK" "$WORK/$BUILDPACK" >/dev/null 2>&1 &&
      pushd "$WORK/$BUILDPACK" >/dev/null
      git -c "advice.detachedHead=false" checkout "v$VERSION"
      popd
    fi
  done
}

# Function to build local buildpacks
build_local_buildpacks() {
  echo "***** Building Local Buildpacks"
  for GROUP in $(yj -t < "$WORK/$BPID/buildpack.toml" | jq -rc '.order[].group[]'); do
  	BUILDPACK=$(echo "$GROUP" | jq -r ".id")
  	VERSION=$(echo "$GROUP" | jq -r ".version")
  	pushd "$WORK/$BUILDPACK" >/dev/null
      if [ "$BUILDPACK" != "paketo-buildpacks/yarn" ] && [ "$BUILDPACK" != "paketo-buildpacks/node-engine" ]; then
        echo "Building $BUILDPACK:$VERSION"
        create-package --destination ./out --version "$VERSION"
        echo "Created package for $BUILDPACK:$VERSION"
        pushd ./out >/dev/null
          pack buildpack package "gcr.io/$BUILDPACK:$VERSION"
        popd
      else
        echo "Building $BUILDPACK:$VERSION with alternate script"
        ./scripts/package.sh --version "$VERSION"
        pack buildpack package "gcr.io/$BUILDPACK:$VERSION" --path ./build/buildpack.tgz
      fi
  	popd
  done
}

# Function to update metadata dependencies
update_metadata_dependencies() {
    echo "**** update_metadata_dependencies"
    printf "%s" "$1" | jq -c '.metadata.dependencies[]' | while read -r i; do
      #printf %s\n $i
      #grab the sha256
      SHA256_REPLACE=$(printf %s "$i" | jq -r .sha256)
      #printf "SHA256_REPLACE %s\n" "$SHA256_REPLACE"
      URI_RESOURCE=$(printf %s "$i" | jq -r .uri)
      #printf "URI_RESOURCE %s\n" "$URI_RESOURCE"
      echo "---> downloading $URI_RESOURCE"
      wget -q --show-progress "$URI_RESOURCE" --output-document=$WORK/downloaded.tgz >/dev/null 2>&1 &&
      SHA256_NEW=$(shasum -a 256 $WORK/downloaded.tgz | cut -d ' ' -f 1)
      #printf "SHA256_NEW %s\n" "$SHA256_NEW"
      sed -i.bak -e "s/$SHA256_REPLACE/$SHA256_NEW/" -- "${TARGET}" && rm -- "${TARGET}.bak"
    done
    echo "**** done"
}

# Functions for specific buildpacks work
java_work(){
  # Bellsoft Liberica
  TARGET=$WORK/paketo-buildpacks/bellsoft-liberica/buildpack.toml
  cp "${TARGET}" "${TARGET}.orig"
  sed -i.bak -e 's/arch=amd64/arch=arm64/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  sed -i.bak -e 's/-amd64.tar.gz/-aarch64.tar.gz/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  update_metadata_dependencies "$(yj -t < ${TARGET})"

  # Syft
  TARGET=$WORK/paketo-buildpacks/syft/buildpack.toml
  cp "${TARGET}" "${TARGET}.orig"
  sed -i.bak -e 's/amd64.tar.gz/arm64.tar.gz/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  update_metadata_dependencies "$(yj -t < ${TARGET})"

  #Watchexec
  TARGET=$WORK/paketo-buildpacks/watchexec/buildpack.toml
  cp "${TARGET}" "${TARGET}.orig"
  sed -i.bak -e 's/arch=amd64/arch=arm64/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  sed -i.bak -e 's/x86_64-unknown/aarch64-unknown/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  update_metadata_dependencies "$(yj -t < ${TARGET})"

  #Java Buildpack
  TARGET=$WORK/$BPID/buildpack.toml
  cp "${TARGET}" "${TARGET}.orig"
  sed -i.bak -e "s/{{.version}}/$BPVER/" -- "${TARGET}" && rm -- "${TARGET}.bak"

  build_local_buildpacks $BPID

  #cd $WORK/$BPID
  pushd "$WORK/$BPID" >/dev/null
    printf "[buildpack]\n  uri = \".\"\n" > ./package-mod.toml
    cat ./package.toml >> ./package-mod.toml 
    echo "********Building $BPID from $PWD"
    pack buildpack package gcr.io/paketo-buildpacks/java:"${BPVER}" --pull-policy=never --config ./package-mod.toml
  popd
}

java_native_image_work(){
  #UPX
  TARGET=$WORK/paketo-buildpacks/upx/buildpack.toml
  cp "${TARGET}" "${TARGET}.orig"
  sed -i.bak -e 's/amd64/arm64/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  #sed -i.bak -e 's/id = \"paketo-buildpacks\/upx\"/id = \"dashaun\/upx\"/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  update_metadata_dependencies "$(yj -t < ${TARGET})"

  #Java Native Image Buildpack
  TARGET=$WORK/$BPID/buildpack.toml
  cp "${TARGET}" "${TARGET}.orig"
  sed -i.bak -e "s/{{.version}}/$BPVER/" -- "${TARGET}" && rm -- "${TARGET}.bak"

  build_local_buildpacks $BPID
  pushd "$WORK/$BPID" >/dev/null
    printf "[buildpack]\n  uri = \".\"\n" > ./package-mod.toml
    cat ./package.toml >> ./package-mod.toml
    echo "********Building $BPID"
    pack buildpack package gcr.io/paketo-buildpacks/java-native-image:"${BPVER}" --pull-policy=never --config ./package-mod.toml
  popd
}

# Main script execution
init
clone_buildpack paketo-buildpacks/java "$JAVA_VER"
java_work
clone_buildpack paketo-buildpacks/java-native-image "$JAVA_NATIVE_IMAGE_VER"
java_native_image_work

cp $WORK/builder.toml $WORK/tiny-builder.toml
cp $WORK/builder.toml $WORK/base-builder.toml

#Tiny Builder
TARGET=$WORK/tiny-builder.toml
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
cat "${PWD}"/stack/jammy-tiny-stack.toml >> "${TARGET}"

##Base Builder
TARGET=$WORK/base-builder.toml
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
sed -i.bak -e '$d' -- "${TARGET}" && rm -- "${TARGET}.bak"
cat "${PWD}"/stack/jammy-base-stack.toml >> "${TARGET}"

pushd $WORK
  pack builder create dashaun/builder-arm:$(date +%Y%m%d) -c ./tiny-builder.toml --pull-policy never
  pack builder create dashaun/base-builder-arm:$(date +%Y%m%d) -c ./base-builder.toml --pull-policy never
popd

docker push dashaun/builder-arm:$(date +%Y%m%d)
docker push dashaun/base-builder-arm:$(date +%Y%m%d)

docker manifest create dashaun/builder:tiny --amend dashaun/builder-arm:$(date +%Y%m%d) --amend paketobuildpacks/builder:tiny
docker manifest push dashaun/builder:tiny
docker manifest create dashaun/builder:$(date +%Y%m%d) --amend dashaun/builder-arm:$(date +%Y%m%d) --amend paketobuildpacks/builder:tiny
docker manifest push dashaun/builder:$(date +%Y%m%d)
docker manifest create dashaun/builder-multiarch:latest --amend dashaun/builder-arm:$(date +%Y%m%d) --amend paketobuildpacks/builder:tiny
docker manifest push dashaun/builder-multiarch:latest
docker manifest create dashaun/builder-multiarch:tiny --amend dashaun/builder-arm:$(date +%Y%m%d) --amend paketobuildpacks/builder:tiny
docker manifest push dashaun/builder-multiarch:tiny
docker manifest create dashaun/builder-multiarch:$(date +%Y%m%d) --amend dashaun/builder-arm:$(date +%Y%m%d) --amend paketobuildpacks/builder:tiny
docker manifest push dashaun/builder-multiarch:$(date +%Y%m%d)

docker manifest create dashaun/builder:base --amend dashaun/base-builder-arm:$(date +%Y%m%d) --amend paketobuildpacks/builder:base
docker manifest push dashaun/builder:base# ... (rest of the script remains the same)
