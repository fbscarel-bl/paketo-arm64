#!/bin/bash
set -euxo pipefail

WORK="./buildpacks"

if [ -z "$WORK" ]; then
	echo "WORK cannot be empty"
	exit 254
fi

init () {
  mkdir -p "$WORK"
  rm -rf "${WORK:?}/"*

  # A link for the renamed buildpacks
  mkdir -p "$WORK/paketo-buildpacks"
  ln -s "${PWD}/${WORK}/paketo-buildpacks" "${PWD}/${WORK}/dashaun"

  wget -q https://raw.githubusercontent.com/paketo-buildpacks/builder-jammy-tiny/main/builder.toml -O $WORK/builder.toml >/dev/null 2>&1 &&

  JAVA_NATIVE_IMAGE_VER=$(cat $WORK/builder.toml | grep "docker://gcr.io/paketo-buildpacks/java-native-image:" | cut -d ':' -f 3 | cut -d '"' -f1)
  JAVA_VER=$(cat $WORK/builder.toml | grep "docker://gcr.io/paketo-buildpacks/java:" | cut -d ':' -f 3 | cut -d '"' -f1)
  PROCFILE_VER=$(cat $WORK/builder.toml | grep "docker://gcr.io/paketo-buildpacks/procfile:" | cut -d ':' -f 3 | cut -d '"' -f1)
  GO_VER=$(cat $WORK/builder.toml | grep "docker://gcr.io/paketo-buildpacks/go:" | cut -d ':' -f 3 | cut -d '"' -f1)

  docker pull paketobuildpacks/build-jammy-tiny:latest
  docker pull paketobuildpacks/run-jammy-tiny:latest
  docker pull dmikusa/build-jammy-base:0.0.2
  docker pull dmikusa/run-jammy-base:0.0.2

  docker pull gcr.io/paketo-buildpacks/procfile:$PROCFILE_VER
  docker pull gcr.io/paketo-buildpacks/go:$GO_VER
}

clone_buildpack (){
  BPID="$1"
  BPVER="$2"
  git clone -q "https://github.com/$BPID" "$WORK/$BPID" >/dev/null 2>&1 &&
  pushd "$WORK/$BPID" >/dev/null
  git -c "advice.detachedHead=false" checkout "v$BPVER"
  popd

  if [ ${1} == "paketo-buildpacks/java" ]; then
    cat << EOF >> $WORK/paketo-buildpacks/java/buildpack.toml

  [[order.group]]
    id = "paketo-buildpacks/new-relic"
    optional = true
    version = "8.6.0"
EOF

    cat << EOF >> $WORK/paketo-buildpacks/java/package.toml

[[dependencies]]
  uri = "docker://gcr.io/paketo-buildpacks/new-relic:8.6.0"
EOF
  fi

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

  # Watchexec
  TARGET=$WORK/paketo-buildpacks/watchexec/buildpack.toml
  cp "${TARGET}" "${TARGET}.orig"
  sed -i.bak -e 's/arch=amd64/arch=arm64/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  sed -i.bak -e 's/x86_64-unknown/aarch64-unknown/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  update_metadata_dependencies "$(yj -t < ${TARGET})"

  # New Relic
  TARGET=$WORK/paketo-buildpacks/new-relic/buildpack.toml
  cp "${TARGET}" "${TARGET}.orig"
  sed -i.bak -e 's/arch=amd64/arch=arm64/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  sed -i.bak -e 's/_amd64.tar.gz/_arm64.tar.gz/' -- "${TARGET}" && rm -- "${TARGET}.bak"
  update_metadata_dependencies "$(yj -t < ${TARGET})"

  # Java Buildpack
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

tag="$(date +"%Y_%m_%d_%H_%M_%S")"
repo="fbscarelbl"

pushd $WORK
  pack builder create ${repo}/builder-arm:${tag} -c ./tiny-builder.toml --pull-policy never
  pack builder create ${repo}/base-builder-arm:${tag} -c ./base-builder.toml --pull-policy never
popd

docker push ${repo}/builder-arm:${tag}
docker push ${repo}/base-builder-arm:${tag}

docker manifest create ${repo}/builder:tiny --amend ${repo}/builder-arm:${tag} --amend paketobuildpacks/builder-jammy-tiny:latest
docker manifest push ${repo}/builder:tiny
docker manifest create ${repo}/builder:${tag} --amend ${repo}/builder-arm:${tag} --amend paketobuildpacks/builder-jammy-tiny:latest
docker manifest push ${repo}/builder:${tag}
docker manifest create ${repo}/builder-multiarch:latest --amend ${repo}/builder-arm:${tag} --amend paketobuildpacks/builder-jammy-tiny:latest
docker manifest push ${repo}/builder-multiarch:latest
docker manifest create ${repo}/builder-multiarch:tiny --amend ${repo}/builder-arm:${tag} --amend paketobuildpacks/builder-jammy-tiny:latest
docker manifest push ${repo}/builder-multiarch:tiny
docker manifest create ${repo}/builder-multiarch:${tag} --amend ${repo}/builder-arm:${tag} --amend paketobuildpacks/builder-jammy-tiny:latest
docker manifest push ${repo}/builder-multiarch:${tag}

docker manifest create ${repo}/builder:base --amend ${repo}/base-builder-arm:${tag} --amend paketobuildpacks/builder-jammy-base:latest
docker manifest push ${repo}/builder:base
