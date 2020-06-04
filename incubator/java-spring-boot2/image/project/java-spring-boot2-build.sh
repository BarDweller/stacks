#!/bin/bash
if [ -n "$TERM" ] && [ "$TERM" != "dumb" ] && [ -x /usr/bin/tput ] && [[ `tput colors` != "0" ]]; then
  color_prompt="yes"
else
  color_prompt=
fi

if [[ "$color_prompt" == "yes" ]]; then
       BLUE="\033[0;34m"
      GREEN="\033[0;32m"
      WHITE="\033[1;37m"
        RED="\033[0;31m"
     YELLOW="\033[0;33m"
   NO_COLOR="\033[0m"
  MVN_COLOR=""
else
        BLUE=""
      GREEN=""
      WHITE=""
        RED=""
   NO_COLOR=""
  MVN_COLOR="-Dstyle.color=never"
fi

note() {
  echo -e "${BLUE}$@${NO_COLOR}"
}
warn() {
  echo -e "${YELLOW}$@${NO_COLOR}"
}
error() {
  echo -e "${RED}$@${NO_COLOR}"
}

run_mvn () {
  echo -e "${GREEN}> mvn $@${NO_COLOR}"
  mvn --no-transfer-progress ${MVN_COLOR} "$@"
}

exec_run_mvn () {
  echo -e "${GREEN}> mvn $@${NO_COLOR}"
  exec mvn --no-transfer-progress ${MVN_COLOR} "$@"
}

common() {
  # Use project util (https://github.com/IBM/project-util) to 
  #  - verify presence of pom.xml, maven repo
  #  - install parent pom if missing
  #  - verify child has expected parent
  #  - verify child parent version is compatible with parent
  # (note: has to be run for a dir that does not have a pom.xml, 
  #  else maven will attempt to load that pom, and will fail if the parent is invalid, 
  #  preventing the plugin from being able to say why!)
  cd /project && \
  run_mvn com.ibm.cloud:project-util-plugin:check-parent-pom \
    -Dparent_path=/project/appsody-boot2-pom.xml \
    -Dchild_path=/project/user-app/pom.xml \
    -Dmaven.repo.local=/mvn/repository
  [ $? != 0 ] && error "Project could not be verified" && exit $RC
  cd /project/user-app
}

recompile() {
  note "Compile project in the foreground"
  exec_run_mvn compile 
}

package() {
  run_mvn clean package
  mkdir -p target/dependency && (cd target/dependency; jar -xf ../*.jar)
}

createStartScript() {
  if [ ! -d target/dependency ]; then
    error "Application must be packaged first"
    exit 1
  fi
  echo '#!/bin/sh' > target/start.sh
  echo 'exec java $JVM_ARGS -cp /app:/app/lib/* -Djava.security.egd=file:/dev/./urandom \' >> target/start.sh
  cat target/dependency/META-INF/MANIFEST.MF | grep 'Start-Class: ' | cut -d' ' -f2 | tr -d '\r\n' >> target/start.sh
  echo "" >> target/start.sh
  cat target/start.sh
  chmod +x target/start.sh
}

debug() {
  note "Build and debug project in the foreground"
  exec_run_mvn -Dmaven.test.skip=true \
    -Dspring-boot.run.jvmArguments='-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=y,address=5005' \
    spring-boot:run
}

run() {
  note "Build and run project in the foreground"
  exec_run_mvn -Dmaven.test.skip=true \
    clean spring-boot:run
}

test() {
  note "Test project in the foreground"
  exec_run_mvn package test
}

#set the action, default to fail text if none passed.
ACTION=
if [ $# -ge 1 ]; then
  ACTION=$1
  shift
fi

case "${ACTION}" in
  recompile)
    export APPSODY_DEV_MODE=run
    recompile
  ;;
  package)
    common
    package
  ;;
  createStartScript)
    createStartScript
  ;;
  debug)
    common
    export APPSODY_DEV_MODE=debug
    debug
  ;;
  run)
    common
    export APPSODY_DEV_MODE=run
    run
  ;;
  test)
    common
    export APPSODY_DEV_MODE=test
    test
  ;;
  *)
    error "Unexpected script usage, expected one of recompile, package, debug, run, test"
  ;;
esac
