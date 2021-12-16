#!/bin/bash

#Release TDB

#  Install p7zip-full and jq from apt-get as prerequisite

#  1. environmental variables
#GITHUB_TOKEN=
REPO_OWNER=jackpoz
REPO_URL=https://github.com/${REPO_OWNER}/TrinityCore.git
PUSH_URL=https://${GITHUB_TOKEN}@github.com/${REPO_OWNER}/TrinityCore.git
GITHUB_API=https://api.github.com/repos/${REPO_OWNER}/TrinityCore/releases

#  2. stop if any error happen
set -e

#  3. clone the repo
git clone --branch=3.3.5 $REPO_URL server
cd server
git config user.email "tdb-release@build.bot" && git config user.name "TDB Release"
git status

#  4. setup the test db and check sql updates
mysql -uroot -proot -e "SET PASSWORD FOR root@localhost='';"
mysql -uroot -e 'create database test_mysql;'
mysql -uroot < sql/create/create_mysql.sql
chmod +x contrib/check_updates.sh
mysql -utrinity -ptrinity auth < sql/base/auth_database.sql
./contrib/check_updates.sh auth 3.3.5 auth localhost
mysql -utrinity -ptrinity characters < sql/base/characters_database.sql
./contrib/check_updates.sh characters 3.3.5 characters localhost
mysql -utrinity -ptrinity world < sql/base/dev/world_database.sql
cat sql/updates/world/3.3.5/*.sql | mysql -utrinity -ptrinity world
mysql -uroot < sql/create/drop_mysql_8.sql

#  5. re-create the db to be used later
mysql -uroot < sql/create/create_mysql.sql

#  6. build everything
mkdir bin
cd bin
cmake ../ -DWITH_WARNINGS=1 -DWITH_COREDEBUG=0 -DUSE_COREPCH=1 -DUSE_SCRIPTPCH=1 -DTOOLS=1 -DSCRIPTS=dynamic -DSERVERS=1 -DNOJEM=0 -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_FLAGS="-Werror" -DCMAKE_CXX_FLAGS="-Werror" -DCMAKE_C_FLAGS_DEBUG="-DNDEBUG" -DCMAKE_CXX_FLAGS_DEBUG="-DNDEBUG" -DCMAKE_INSTALL_PREFIX=check_install
c++ --version
make -j 4 -k && make install
cd check_install/bin
./authserver --version
./worldserver --version
cp ../etc/worldserver.conf.dist ../etc/worldserver.conf

#  7. download latest TDB
OLD_TDB_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/TrinityCore/TrinityCore/releases)
OLD_TDB=$(echo $OLD_TDB_RESPONSE | jq 'map(select(.tag_name|startswith("TDB335"))) | sort_by(.created_at) | reverse | .[0]')
OLD_TDB_VERSION=$(echo $OLD_TDB | jq -r '.tag_name | split(".")[1]')
OLD_TDB_FOLDER=$OLD_TDB_VERSION'_'`date +%Y_%m_%d`
OLD_TDB_URL=$( echo $OLD_TDB | jq -r '.assets | map(select(.name|endswith("7z"))) | .[0].browser_download_url')
wget $OLD_TDB_URL -q -O TDB.7z
7z e TDB.7z

#  8. set new TDB name and sql name
NEW_TDB_VERSION=`date +%y%m1`
if [ $NEW_TDB_VERSION == $OLD_TDB_VERSION ]; then
  NEW_TDB_VERSION=$((NEW_TDB_VERSION + 1))
fi
TODAY=`date +%Y_%m_%d`
NEW_TDB_TAG='TDB335.'$NEW_TDB_VERSION
NEW_TDB_NAME='TDB 335.'$NEW_TDB_VERSION
NEW_TDB_FILE='TDB_full_world_335.'$NEW_TDB_VERSION'_'$TODAY
NEW_TDB_RELEASE_NOTES='Release '${NEW_TDB_VERSION: -1}' of '`date +%Y/%m`

#  9. move all sql update scripts to old
cd ../../..
mkdir sql/old/3.3.5a/auth/$OLD_TDB_FOLDER && mv sql/updates/auth/3.3.5/* sql/old/3.3.5a/auth/$OLD_TDB_FOLDER/
mkdir sql/old/3.3.5a/characters/$OLD_TDB_FOLDER && mv sql/updates/characters/3.3.5/* sql/old/3.3.5a/characters/$OLD_TDB_FOLDER/
mkdir sql/old/3.3.5a/world/$OLD_TDB_FOLDER && mv sql/updates/world/3.3.5/* sql/old/3.3.5a/world/$OLD_TDB_FOLDER/
git add sql

# 10. add the first sql update (making sure there isn't already a SQL file with the same name)
# 10.1 auth db
for((counter=0;;counter++))
do
  if [ -f "./sql/old/3.3.5a/auth/$OLD_TDB_FOLDER/"$TODAY"_$(printf "%02d" $counter)_auth.sql" ]; then
    continue
  else
    cat >sql/updates/auth/3.3.5/$TODAY\_$(printf "%02d" $counter)_auth.sql <<EOL
-- $NEW_TDB_NAME auth
UPDATE \`updates\` SET \`state\`='ARCHIVED';
EOL
    break
  fi
done
# 10.2 characters db
for((counter=0;;counter++))
do
  if [ -f "./sql/old/3.3.5a/characters/$OLD_TDB_FOLDER/"$TODAY"_$(printf "%02d" $counter)_characters.sql" ]; then
    continue
  else
    cat >sql/updates/characters/3.3.5/$TODAY\_$(printf "%02d" $counter)_characters.sql <<EOL
-- $NEW_TDB_NAME characters
UPDATE \`updates\` SET \`state\`='ARCHIVED';
EOL
    break
  fi
done
# 10.3 world db
for((counter=0;;counter++))
do
  if [ -f "./sql/old/3.3.5a/world/$OLD_TDB_FOLDER/"$TODAY"_$(printf "%02d" $counter)_world.sql" ] || [ -f "./sql/old/3.3.5a/world/$OLD_TDB_FOLDER/"$TODAY"_$(printf "%02d" $counter)_world_335.sql" ] ; then
    continue
  else
    cat >sql/updates/world/3.3.5/$TODAY\_$(printf "%02d" $counter)_world.sql <<EOL
-- $NEW_TDB_NAME world
UPDATE \`version\` SET \`db_version\`='$NEW_TDB_NAME', \`cache_id\`=$NEW_TDB_VERSION LIMIT 1;
UPDATE \`updates\` SET \`state\`='ARCHIVED';
EOL
    break
  fi
done
git add sql

# 11. let worldserver do the initial import and apply all updates
cd bin/check_install/bin
./worldserver --update-databases-only
cd ../../..

# 12. update db setting ARCHIVED
mysql -uroot -D auth -e "update \`updates\` set \`state\`='ARCHIVED',\`speed\`=0;"
mysql -uroot -D characters -e "update \`updates\` set \`state\`='ARCHIVED',\`speed\`=0;"
mysql -uroot -D world -e "update \`updates\` set \`state\`='ARCHIVED',\`speed\`=0;"
# 12.b reset worldstates in characters db
mysql -uroot -D characters -e "update \`worldstates\` set \`value\`=0;"

# 13. update base dbs sql
mysqldump -uroot auth --default-character-set='utf8' --routines --result-file sql/base/auth_database.sql
sed -i -e 's$VALUES ($VALUES\n($g' sql/base/auth_database.sql
sed -i -e 's$),($),\n($g' sql/base/auth_database.sql
sed -i -e 's/DEFINER=[^*]*\*/\*/' sql/base/auth_database.sql
sed -i -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' sql/base/auth_database.sql
mysqldump -uroot characters --default-character-set='utf8' --routines --result-file sql/base/characters_database.sql
sed -i -e 's$VALUES ($VALUES\n($g' sql/base/characters_database.sql
sed -i -e 's$),($),\n($g' sql/base/characters_database.sql
sed -i -e 's/DEFINER=[^*]*\*/\*/' sql/base/characters_database.sql
sed -i -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' sql/base/auth_database.sql
mysqldump -uroot world --default-character-set='utf8' --routines --no-data --result-file sql/base/dev/world_database.sql
sed -i -e 's/DEFINER=[^*]*\*/\*/' sql/base/dev/world_database.sql
sed -i -e 's/utf8mb4_0900_ai_ci/utf8mb4_unicode_ci/g' sql/base/auth_database.sql
git add sql

# 14. dump world db to sql
mkdir tdb
cd tdb
mysqldump -uroot world --default-character-set='utf8' --routines --result-file $NEW_TDB_FILE.sql
sed -i -e 's/DEFINER=[^*]*\*/\*/' $NEW_TDB_FILE.sql

# 15. 7zip the world db sql file
7z a $NEW_TDB_FILE.7z $NEW_TDB_FILE.sql

# 16. recreate the dbs to test sql base files import
cd ..
mysql -uroot < sql/create/drop_mysql_8.sql
mysql -uroot < sql/create/create_mysql.sql

# 17. test sql base files import
mysql -uroot -D auth < sql/base/auth_database.sql
mysql -uroot -D characters < sql/base/characters_database.sql
mysql -uroot -D world < sql/base/dev/world_database.sql

# 18. recreate the dbs to test TDB import
mysql -uroot < sql/create/drop_mysql_8.sql
mysql -uroot < sql/create/create_mysql.sql

# 19. test TDB import
mysql -uroot -D world < tdb/$NEW_TDB_FILE.sql

# 20. update revision_data.h.in.cmake with new TDB file name
sed -i -e 's$ #define _FULL_DATABASE             "[A-Za-z0-9$_.]*"$ #define _FULL_DATABASE             "'$NEW_TDB_FILE'.sql"$g' revision_data.h.in.cmake
git add revision_data.h.in.cmake
# 21. commit and push
git commit -m "$NEW_TDB_NAME - "`date +%Y/%m/%d`
git push $PUSH_URL >/dev/null 2>&1
# 22. create a tag and push
git tag $NEW_TDB_TAG
git push $PUSH_URL $NEW_TDB_TAG >/dev/null 2>&1
# 23. create a GitHub release
cd tdb
NEW_RELEASE_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" -d '{"tag_name":"'"$NEW_TDB_TAG"'","target_commitish":"3.3.5","name":"'"$NEW_TDB_NAME"'","body":"### ![3.3.5](https://img.shields.io/badge/branch-3.3.5-yellow.svg)\n'"$NEW_TDB_RELEASE_NOTES"'\n","draft":true,"prerelease":false}' $GITHUB_API)
echo $NEW_RELEASE_RESPONSE
curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/octet-stream" $(echo $NEW_RELEASE_RESPONSE | jq -r '.upload_url' | sed -e 's${?name,label}$$g')'?name='"$NEW_TDB_FILE"'.7z'  --data-binary @$NEW_TDB_FILE.7z
curl -s -H "Authorization: token $GITHUB_TOKEN" -X 'PATCH' $(echo $NEW_RELEASE_RESPONSE | jq -r '.url') -d '{"draft":false}'
