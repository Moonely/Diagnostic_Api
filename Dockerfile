# ════════════════════════════════════════════════════════════════════════════
# DOCKERFILE - Spring Boot Application (diagnostic-api)
# ════════════════════════════════════════════════════════════════════════════
#
# Ce Dockerfile utilise une approche multi-étapes (multi-stage build):
# - Étape 1 (builder): Compile le code source en JAR
# - Étape 2 (final): Lance l'application avec le JAR créé
#
# Avantages:
# ✅ Image finale plus petite (sans Maven, source code, etc)
# ✅ Securité accrue (pas de source en production)
# ✅ Build rapide avec cache Docker
# ════════════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1: BUILD - Compiler le projet Maven
# ════════════════════════════════════════════════════════════════════════════

# Utilise une image Java 21 (LTS - Long Term Support)
# eclipse-temurin = Distribution OpenJDK officielle et stable
# :21-jdk = Java 21 avec JDK complet (Maven, compilateur, etc)
FROM eclipse-temurin:21-jdk AS builder

# ────────────────────────────────────────────────────────────────────────────
# Préparation du conteneur builder
# ────────────────────────────────────────────────────────────────────────────

# Définit le répertoire de travail dans le conteneur
# Tous les commandes suivantes s'exécutent dans /app
WORKDIR /app

# Met à jour les packages système et installe Maven
# ⚠️ IMPORTANT: Maven n'est pas dans l'image de base, il faut l'installer!
RUN apt-get update && \
    apt-get install -y maven && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ────────────────────────────────────────────────────────────────────────────
# Copie du code source
# ────────────────────────────────────────────────────────────────────────────

# Copie le fichier pom.xml du projet local vers /app/pom.xml du conteneur
# C'est le fichier de configuration Maven (dépendances, plugins, etc)
COPY pom.xml .

# Copie le répertoire src/ du projet local vers /app/src/ du conteneur
# Contient tout le code source Java
COPY src ./src

# ────────────────────────────────────────────────────────────────────────────
# Build du projet
# ────────────────────────────────────────────────────────────────────────────

# Lance Maven pour compiler et packager l'application
# Explications des options:
# - clean       = Nettoie les builds antérieurs
# - package     = Compile et crée le JAR
# - -DskipTests = Saute les tests pour accélérer le build
#                 (Les tests ont déjà été exécutés dans GitHub Actions)
#
# Résultat: Un fichier diagnostic-api.jar dans /app/target/
RUN mvn clean package -DskipTests

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2: RUNTIME - Image finale pour lancer l'application
# ════════════════════════════════════════════════════════════════════════════

# Utilise une image Java 21 JDK Jammy (Ubuntu-based)
# Cette image est plus légère car elle n'a que le runtime Java (pas Maven)
FROM eclipse-temurin:21-jdk-jammy

# ────────────────────────────────────────────────────────────────────────────
# Préparation de l'image finale
# ────────────────────────────────────────────────────────────────────────────

# Définit le répertoire de travail
WORKDIR /app

# ────────────────────────────────────────────────────────────────────────────
# Copie du JAR depuis l'étape builder
# ────────────────────────────────────────────────────────────────────────────

# Copie le JAR compilé de l'étape builder vers l'image finale
# Syntaxe: COPY --from=<stage> <source> <destination>
#
# - --from=builder      = Copie depuis l'étape nommée 'builder'
# - /app/target/diagnostic-api.jar = Fichier source (créé par Maven)
# - app.jar            = Nom du fichier dans l'image finale
#
# Note: Seul le JAR est copié, pas les sources ni Maven!
#       Cela rend l'image beaucoup plus petite et sécurisée
COPY --from=builder /app/target/diagnostic-api.jar app.jar

# ────────────────────────────────────────────────────────────────────────────
# Configuration de l'application
# ────────────────────────────────────────────────────────────────────────────

# Expose le port 8080
# ⚠️ IMPORTANT: C'est seulement une déclaration de documentation
#               Le port doit être mappé à la création du conteneur:
#               docker run -p 8080:8080 diagnostic-api:latest
EXPOSE 8080

# ────────────────────────────────────────────────────────────────────────────
# Health Check (optionnel mais recommandé)
# ────────────────────────────────────────────────────────────────────────────

# Vérifie régulièrement que l'application est en bonne santé
# - --interval=30s      = Vérifie chaque 30 secondes
# - --timeout=3s        = Timeout après 3 secondes
# - --start-period=40s  = Attend 40s au démarrage avant les premiers checks
# - --retries=3         = Marque comme unhealthy après 3 échecks
#
# Commande: Vérifie que le port 8080 répond
# (Nécessite curl ou autre outil dans l'image)
# Décommenter si vous le voulez:
# HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
#     CMD curl -f http://localhost:8080/health || exit 1

# ────────────────────────────────────────────────────────────────────────────
# Commande de démarrage
# ────────────────────────────────────────────────────────────────────────────

# ENTRYPOINT = Point d'entrée du conteneur
# Lance la JVM et exécute le JAR Spring Boot
# Syntaxe JSON = Exécute directement (sans passer par un shell)
#
# java -jar app.jar = Lance l'application
#                     Le fichier app.jar contient l'application Spring Boot
#                     complète avec toutes les dépendances (fat JAR)
ENTRYPOINT ["java", "-jar", "app.jar"]

# ════════════════════════════════════════════════════════════════════════════
# NOTES DE DÉPLOIEMENT
# ════════════════════════════════════════════════════════════════════════════
#
# 1. BUILD LOCAL:
#    docker build -t diagnostic-api:latest .
#
# 2. RUN LOCAL:
#    docker run -p 8080:8080 diagnostic-api:latest
#
# 3. TESTER:
#    curl http://localhost:8080/health
#
# 4. PUSH À DOCKER HUB:
#    docker tag diagnostic-api:latest tonusername/diagnostic-api:latest
#    docker push tonusername/diagnostic-api:latest
#
# 5. TAILLE DE L'IMAGE:
#    - Étape 1 (builder): ~600MB (Maven, JDK, code source)
#    - Étape 2 (final):   ~200MB (JDK, JAR seulement)
#    ✅ L'image finale est 3x plus petite!
#
# ════════════════════════════════════════════════════════════════════════════
