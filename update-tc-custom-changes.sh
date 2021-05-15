#!/bin/bash

# stop if any error happen
set -e

# before install
git config user.email "github.actions@build.bot" && git config user.name "Github Actions"
git clone --branch=${BRANCH} https://github.com/TrinityCore/TrinityCoreCustomChanges.git server
cd server
git status
if [ -n "$BASE_BRANCH" ]; then
  git remote add BaseRemote https://github.com/TrinityCore/TrinityCoreCustomChanges.git
else
  git remote add BaseRemote https://github.com/TrinityCore/TrinityCore.git
  export BASE_BRANCH=3.3.5
fi
git fetch BaseRemote ${BASE_BRANCH}
git merge -m "Merge ${BASE_BRANCH} to ${BRANCH}" BaseRemote/${BASE_BRANCH}
git submodule update --init --recursive
git status

# install
mysql -uroot -e 'create database test_mysql;'
mkdir bin
cd bin
cmake ../ -DWITH_WARNINGS=1 -DWITH_COREDEBUG=0 -DUSE_COREPCH=1 -DUSE_SCRIPTPCH=1 -DTOOLS=1 -DSCRIPTS=dynamic -DSERVERS=1 -DNOJEM=0 -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_FLAGS="-Werror" -DCMAKE_CXX_FLAGS="-Werror" -DCMAKE_C_FLAGS_DEBUG="-DNDEBUG" -DCMAKE_CXX_FLAGS_DEBUG="-DNDEBUG" -DCMAKE_INSTALL_PREFIX=check_install
cd ..
chmod +x contrib/check_updates.sh

# script
c++ --version
mysql -uroot < sql/create/create_mysql.sql
mysql -utrinity -ptrinity auth < sql/base/auth_database.sql
./contrib/check_updates.sh auth 3.3.5 auth localhost
mysql -utrinity -ptrinity characters < sql/base/characters_database.sql
./contrib/check_updates.sh characters 3.3.5 characters localhost
mysql -utrinity -ptrinity world < sql/base/dev/world_database.sql
cat sql/updates/world/3.3.5/*.sql | mysql -utrinity -ptrinity world
mysql -uroot < sql/create/drop_mysql.sql
cd bin
make -j 4 -k && make install
cd check_install/bin
./authserver --version
./worldserver --version

# after success
git push https://${GITHUB_TOKEN}@github.com/TrinityCore/TrinityCoreCustomChanges.git HEAD:${BRANCH}
