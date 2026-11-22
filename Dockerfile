FROM eclipse-temurin:25-jdk AS build

WORKDIR /workspace

COPY mvnw pom.xml ./
COPY .mvn/ .mvn/
RUN chmod +x mvnw

COPY src/ src/
RUN ./mvnw -B clean package

FROM eclipse-temurin:25-jre

WORKDIR /app

RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

COPY --from=build --chown=10001:10001 /workspace/target/mi_foro_usuarios-0.0.1-SNAPSHOT.jar /app/app.jar

USER 10001:10001

EXPOSE 8081

ENTRYPOINT ["java", "-jar", "/app/app.jar"]