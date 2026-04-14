# apps_nacos

`apps_nacos` 是单点 Nacos 的离线交付仓库，延续当前中间件 `.run` 安装器的统一范式：

- 多架构离线包：`amd64` / `arm64`
- 内网镜像预热
- `install | uninstall | status | help` 四类动作
- 默认开启 metrics 与 `ServiceMonitor`
- 安装阶段可自动初始化 Nacos 数据库和标准业务配置

当前默认镜像保持不升级，继续使用：

- `registry.cn-beijing.aliyuncs.com/kube4/nacos-server:v2.3.0-slim`

## 这次改动的重点

为了解决 `frame_nacos_demo.sql` 或 `cmict-share.yaml` 变大后触发 ConfigMap 大小限制的问题，安装器已经改成：

- 不再创建 `nacos-bootstrap-assets` ConfigMap
- 不再创建 `nacos-bootstrap-db-auth` Secret
- 不再创建 `nacos-db-bootstrap` Job
- 安装器解包后，直接调用随包附带的 `import-nacos.sh`
- `import-nacos.sh` 使用本机 `kubectl exec -i` 把 SQL 和 YAML 流式导入到 MySQL Pod

这条链路更适合大文件，也更符合离线环境实际使用方式。

## 默认部署契约

直接执行：

```bash
./nacos-installer-amd64.run install --mysql-password '<MYSQL_PASSWORD>' -y
```

默认值如下：

- namespace: `aict`
- replicas: `1`
- image: `sealos.hub:5000/kube4/nacos-server:v2.3.0-slim`
- MySQL host: `mysql-0.mysql.aict`
- MySQL namespace: `aict`
- MySQL pod: 自动根据 `--mysql-host` 首段或 `--mysql-label` 识别
- MySQL label fallback: `app=mysql`
- MySQL container: `mysql`
- MySQL database: `frame_nacos_demo`
- MySQL user: `root`
- Nacos HTTP NodePort: `30094`
- Nacos gRPC NodePort: `30930`
- metrics: `true`
- ServiceMonitor: `true`
- resource profile: `mid`
- DB bootstrap: `true`
- `cmict-share.yaml` import: `true`
- target registry repo: `sealos.hub:5000/kube4`

## 安装器执行流程

`install` 默认执行顺序：

1. 解包 `.run` 中的 manifest、镜像元数据、SQL、配置文件和导入脚本
2. 将离线镜像推送到目标内网仓库
3. 检查集群是否支持 `ServiceMonitor`
4. 通过本机 `kubectl` 调用 `import-nacos.sh`
5. 由 `import-nacos.sh` 直接把标准 SQL 导入 MySQL
6. 由 `import-nacos.sh` 直接把最新版 `cmict-share.yaml` 写入 `config_info`
7. 部署 Nacos `Deployment / Service / ServiceMonitor`
8. 等待 Deployment ready

## 为什么这种方案更稳

旧链路的问题：

- 大 SQL + 大 YAML 一起塞到 ConfigMap，容易撞 `1MiB` 左右大小边界
- 多层 shell / YAML / SQL 转义很脆
- 初始化失败时排障链路长

新链路的优点：

- SQL 与 YAML 直接从本地文件走标准输入流进入 MySQL
- 不依赖 ConfigMap 大小
- 不依赖临时 bootstrap Job
- 现场可单独重跑 `import-nacos.sh`

## 快速开始

### 1. 查看帮助

```bash
./nacos-installer-amd64.run --help
./nacos-installer-amd64.run help
```

### 2. 用默认参数安装

```bash
./nacos-installer-amd64.run install \
  --mysql-password '<MYSQL_PASSWORD>' \
  -y
```

### 3. 指定 MySQL Pod 所在命名空间

如果 MySQL 不在 Nacos 同一个 namespace：

```bash
./nacos-installer-amd64.run install \
  --mysql-namespace mysql-system \
  --mysql-password '<MYSQL_PASSWORD>' \
  -y
```

### 4. 显式指定 MySQL Pod

如果自动识别不到 Pod，直接指定最稳：

```bash
./nacos-installer-amd64.run install \
  --mysql-pod mysql-0 \
  --mysql-password '<MYSQL_PASSWORD>' \
  -y
```

### 5. 只部署 Nacos，不导入数据库

```bash
./nacos-installer-amd64.run install \
  --disable-db-bootstrap \
  --disable-cmict-share-import \
  --mysql-password '<MYSQL_PASSWORD>' \
  -y
```

## `import-nacos.sh` 独立使用手册

安装器内部调用的就是这个脚本。你也可以在现场单独执行它：

```bash
./import-nacos.sh \
  --mysql-password '<MYSQL_PASSWORD>'
```

常见用法：

```bash
./import-nacos.sh \
  --mysql-namespace aict \
  --mysql-pod mysql-0 \
  --mysql-password '<MYSQL_PASSWORD>' \
  --sql-file ./frame_nacos_demo.sql \
  --config-file ./cmict-share.yaml
```

如果只想导配置，不想重复导 SQL：

```bash
./import-nacos.sh \
  --mysql-password '<MYSQL_PASSWORD>' \
  --skip-sql-import
```

如果只想补标准 SQL，不想覆盖 `cmict-share.yaml`：

```bash
./import-nacos.sh \
  --mysql-password '<MYSQL_PASSWORD>' \
  --skip-config-import
```

## 默认资源需求

`--resource-profile` 支持 `low|mid|midd|high`：

| Profile | Request | Limit | 说明 |
| --- | --- | --- | --- |
| `low` | `200m / 512Mi` | `500m / 1Gi` | demo、开发自测 |
| `mid` | `500m / 1Gi` | `1 / 2Gi` | 默认，适合普通共享环境 |
| `high` | `1 / 2Gi` | `2 / 4Gi` | 更高并发或更重配置中心负载 |

默认是单副本，所以稳态资源需求就是上面 Nacos 单 Pod 的值。

## 默认访问地址

### 集群内

- `http://nacos.aict.svc.cluster.local:8848/nacos`
- `nacos.aict.svc.cluster.local:8848`

### 集群外

- HTTP: `http://<NODE_IP>:30094/nacos`
- gRPC: `<NODE_IP>:30930`

## 监控契约

默认开启：

- metrics
- `ServiceMonitor`

抓取路径：

- `/nacos/actuator/prometheus`

默认标签：

- `monitoring.archinfra.io/stack=default`

如果集群没有 `ServiceMonitor` CRD，安装器会自动跳过 `ServiceMonitor`，但不会因此让整套 Nacos 安装失败。

## 和其他组件的关系

Nacos 默认依赖：

- MySQL

默认不依赖：

- Redis
- MinIO
- RabbitMQ
- MongoDB
- Milvus

但 `cmict-share.yaml` 里可能会引用你们业务环境里的其他中间件地址或账号，所以在生产环境导入前，建议先审阅这份 YAML。

## 构建

```bash
./build.sh --arch amd64
./build.sh --arch arm64
./build.sh --arch all
```

输出产物：

- `dist/nacos-installer-amd64.run`
- `dist/nacos-installer-amd64.run.sha256`
- `dist/nacos-installer-arm64.run`
- `dist/nacos-installer-arm64.run.sha256`

## 排障建议

### 1. 先看安装器帮助

```bash
./nacos-installer-amd64.run --help
```

### 2. 看 Nacos 资源状态

```bash
./nacos-installer-amd64.run status -n aict
kubectl get pods,svc,deploy,configmap -n aict
kubectl logs -n aict deploy/nacos
```

### 3. MySQL 导入失败时

优先检查：

- `kubectl` 当前上下文是否正确
- `--mysql-namespace` 是否正确
- `--mysql-pod` 是否正确
- `--mysql-container` 是否正确
- `--mysql-password` 是否正确

建议直接独立重跑：

```bash
./import-nacos.sh \
  --mysql-namespace aict \
  --mysql-pod mysql-0 \
  --mysql-password '<MYSQL_PASSWORD>'
```

### 4. 自动识别 MySQL Pod 失败时

安装器现在的自动识别顺序是：

1. 如果显式传了 `--mysql-pod`，直接使用
2. 否则尝试从 `--mysql-host` 取首段，例如 `mysql-0.mysql.aict` -> `mysql-0`
3. 如果该 Pod 不存在，再回退到 `--mysql-label`

所以最稳妥的做法仍然是显式传 `--mysql-pod`。
