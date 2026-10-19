# syntax=docker/dockerfile:1

# --- build: compila el jar (las pruebas y el formato los cubre el CI) ---
FROM eclipse-temurin:25-jdk-noble AS build
WORKDIR /workspace
COPY --chmod=755 mvnw .
COPY .mvn .mvn
COPY pom.xml .
COPY src src
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -ntp package -DskipTests -Dspotless.check.skip=true \
    && cp target/*.jar app.jar \
    && java -Djarmode=tools -jar app.jar extract --layers --launcher --destination extracted

# --- runtime: solo JRE, usuario sin privilegios, capas de Spring Boot ---
FROM eclipse-temurin:25-jre-noble
RUN groupadd --system spring && useradd --system --gid spring spring \
    && mkdir -p /data/avatars && chown spring:spring /data/avatars
WORKDIR /app
COPY --from=build /workspace/extracted/dependencies/ ./
COPY --from=build /workspace/extracted/spring-boot-loader/ ./
COPY --from=build /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build /workspace/extracted/application/ ./
USER spring
EXPOSE 8080
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
