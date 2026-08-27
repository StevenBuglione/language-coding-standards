# Runtime-only image: official base, no quality tools baked in.
# Every tool installs during bootstrap from build.gradle.kts at pinned versions.
# gradle:8.14-jdk21 = Gradle 8.14.x on Eclipse Temurin JDK 21 (ships git).
FROM gradle:8.14-jdk21

# Tool caches stay inside the mounted workspace (CONTRACTS.md §5):
# GRADLE_USER_HOME holds the dependency and wrapper caches so nothing leaks
# outside the workspace or into image layers.
ENV GRADLE_USER_HOME=/workspace/.gradle-home \
    GRADLE_OPTS=-Dorg.gradle.daemon=false

WORKDIR /workspace
