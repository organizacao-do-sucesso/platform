# Docker Compose

O ambiente local sobe todos os serviços, o banco, o Redis e a stack de
observabilidade com um único arquivo, `api/compose.yaml`, que inclui o
`compose.yaml` do repositório `observability`.

```bash
git clone --recurse-submodules https://github.com/organizacao-do-sucesso/platform.git
cd platform/api
cp .env.example .env
docker compose up -d --build
```

Os serviços Java precisam do jar em `target/` antes do build da imagem
(`mvn package` em cada `*-service`, depois de `mvn install` nos contratos).

| Endereço | O que é |
| --- | --- |
| `http://localhost:8080` | Gateway (API) |
| `http://localhost:8080/grafana/` | Grafana (`admin` / senha de `GRAFANA_ADMIN_PASSWORD`) |
| `http://localhost:8080/prometheus/` | Prometheus (login da loja com papel `administrator`) |
