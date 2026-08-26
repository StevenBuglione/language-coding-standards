# Runtime-only image: official base, no quality tools baked in.
# Every tool installs during the `deps` phase from pom.xml at pinned versions.
# maven:3.9-eclipse-temurin-25 = Maven 3.9.x on Eclipse Temurin JDK 25 LTS
# (the image ships git, which the container preamble needs).
FROM maven:3.9-eclipse-temurin-25

# MAVEN_CONFIG must be empty for the mvnw wrapper script: the official image
# exports a value that otherwise makes every ./mvnw call fail. Tool caches
# point at workspace-relative gitignored directories (CONTRACTS.md §4):
# MAVEN_USER_HOME holds the wrapper distribution cache, and the local repo is
# passed per-invocation as -Dmaven.repo.local=.m2repo by verify.sh (kept as a
# MAVEN_OPTS fallback so ad-hoc interactive mvn calls land in the same place).
ENV MAVEN_CONFIG= \
    MAVEN_USER_HOME=/workspace/.m2wrapper \
    MAVEN_OPTS=-Dmaven.repo.local=/workspace/.m2repo

WORKDIR /workspace
