#!/bin/bash
bundle version 2>/dev/null
if [ $? != 0 ];then
  echo "bundler is not installed. Please install it."
  exit -1
fi
cd $(dirname $0)

if [ $TRAVIS_BRANCH ];then
  branch=$TRAVIS_BRANCH
else
  branch=$(git rev-parse --abbrev-ref HEAD)
fi
if [ $TRAVIS_COMMIT ];then
  commit=$TRAVIS_COMMIT
else
  commit=$(git rev-parse HEAD)
fi
version=$(sed s/-/~/g ../../VERSION)
version="$version+git$commit"
date=$(date --rfc-2822)
year=$(date +%Y)

# clean
[ ! -d build ] || rm -rf build

additional_native_build_requirements() {
  if [ $1 == "nokogiri" ];then
    echo "BuildRequires: libxml2-devel libxslt-devel\n"
  elif [ $1 == "mysql2" ];then
    echo "BuildRequires: libmysqlclient-devel < 10.1\nRequires: libmysqlclient18 < 10.1\nRecommends: mariadb\n"
  elif [ $1 == "ethon" ];then
    echo "BuildRequires: libcurl-devel\nRequires: libcurl4\n"
  elif [ $1 == "ffi" ];then
    echo "BuildRequires: libffi-devel\n"
  fi
  if [ $1 == "ethon" ];then
    echo "BuildRequires: libcurl-devel\nRequires: libcurl4\n"
  fi
}

mkdir -p build/Portus-$branch
cp -v ../../Gemfile* build/Portus-$branch
cp -v patches/*.patch build/Portus-$branch

pushd build/Portus-$branch/
  echo "apply patches if needed"
  if ls *.patch >/dev/null 2>&1 ;then
      for p in *.patch;do
          number=$(echo "$p" | cut -d"_" -f1)
          patchsources="$patchsources\nPatch$number: $p\n"
          patchexecs="$patchexecs\n%patch$number -p1\n"
          # skip applying rpm patches
          [[ $p =~ .rpm\.patch$ ]] && continue
          echo "applying patch $p"
          patch -p1 < $p || exit -1
      done
  fi
  echo "generate the Gemfile.lock for packaging"
  export BUNDLE_GEMFILE=$PWD/Gemfile
  cp Gemfile.lock Gemfile.lock.orig
  bundle config build.nokogiri --use-system-libraries
  PACKAGING=yes bundle install --retry=3 --no-deployment
  grep "git-review" Gemfile.lock
  if [ $? == 0 ];then
    echo "DEBUG: ohoh something went wrong and you have devel packages"
    diff Gemfile.lock Gemfile.lock.orig
    exit -1
  fi
  echo "get requirements from Gemfile.lock"
  IFS=$'\n' # do not split on spaces
  build_requires=""
  for gem in $(cat Gemfile.lock | grep "    "  | grep "     " -v | sort | uniq);do
    gem_name=$(echo $gem | cut -d" " -f5)
    gem_version=$(echo $gem | cut -d "(" -f2 | cut -d ")" -f1)
    build_requires="$build_requires\nBuildRequires: %{rubygem $gem_name} = $gem_version"
    build_requires="$build_requires\n$(additional_native_build_requirements $gem_name)"
  done
popd

echo "create portus.spec based on portus.spec.in"
cp portus.spec.in portus.spec
sed -e "s/__BRANCH__/$branch/g" -i portus.spec
sed -e "s/__RUBYGEMS_BUILD_REQUIRES__/$build_requires/g" -i portus.spec
sed -e "s/__DATE__/$date/g" -i portus.spec
sed -e "s/__COMMIT__/$commit/g" -i portus.spec
sed -e "s/__VERSION__/$version/g" -i portus.spec
sed -e "s/__CURRENT_YEAR__/$year/g" -i portus.spec
sed -e "s/__PATCHSOURCES__/$patchsources/g" -i portus.spec
sed -e "s/__PATCHEXECS__/$patchexecs/g" -i portus.spec

if [ -f portus.spec ];then
  echo "Done!"
  exit 0
else
  echo "A problem occured creating the spec file."
  exit -1
fi
