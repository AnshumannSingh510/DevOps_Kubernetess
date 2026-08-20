FROM jenkins/jenkins:2.479.2-lts-jdk17

USER root

# Docker CLI (talks to the host's Docker Desktop engine via the mounted socket),
# kubectl (talks to Docker Desktop Kubernetes / Minikube via the mounted kubeconfig),
# and Maven (kept simple here; the Jenkinsfile can also use a Maven Docker agent).
RUN apt-get update && apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        maven \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
    && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl \
    && rm -rf /var/lib/apt/lists/*

# Let the jenkins user access the mounted Docker socket
RUN groupadd -f docker && usermod -aG docker jenkins

USER jenkins

# Pre-install the Jenkins plugins the Jenkinsfile relies on
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
