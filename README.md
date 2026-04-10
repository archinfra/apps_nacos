# apps_nacos

Nacos 单点离线交付仓库。

这个仓库不是只放一个 Deployment manifest，而是把下面几类能力做成了统一的 `.run` 安装包：

- Nacos 本体安装
- MySQL 基线建库建表
- 标准基线配置导入
- metrics / ServiceMonitor 接入
- `amd64` / `arm64` 多架构离线交付
- GitHub Actions 构建与 GitHub Release 发布

它沿用了我们在 MySQL、Redis、MinIO、Milvus 等仓库里已经稳定下来的交付范式，目标是让一个没有项目背景的新同事，或者一个普通 AI，也能只看 README 就完成安装、验证和排障。

## 这套安装器是怎么设计的

普通使用者可以把它理解成一个 “Nacos 离线安装器”，核心只有 4 个动作：

- `install`
- `status`
- `uninstall`
- `help`

其中 `install` 默认会按下面的顺序执行：

1. 解包 `.run` 内的 chart、manifest、镜像元数据和镜像 tar
2. 将内置镜像准备到目标内网仓库
3. 校验集群里是否支持 `ServiceMonitor`
4. 使用 MySQL helper Job 初始化 `frame_nacos_demo`
5. 导入清洗后的标准 SQL
6. 导入最新版 `cmict-share.yaml`
7. 部署 Nacos Deployment / Service / ServiceMonitor
8. 等待 Nacos 就绪并输出结果

这意味着使用者通常不需要自己手动做这些事情：

- `docker load`
- `docker tag`
- `docker push`
- 手工执行 SQL
- 手工把 `cmict-share.yaml` 导进数据库
- 手工写 `ServiceMonitor`

## 默认部署契约

如果你直接执行：

```bash
./nacos-installer-amd64.run install --mysql-password '<MYSQL_PASSWORD>' -y
```

默认值如下：

- namespace: `aict`
- replicas: `1`
- image: `sealos.hub:5000/kube4/nacos-server:v2.3.0-slim`
- MySQL host: `mysql-0.mysql.aict`
- MySQL port: `3306`
- MySQL database: `frame_nacos_demo`
- MySQL user: `root`
- Nacos HTTP NodePort: `30094`
- Nacos gRPC NodePort: `30930`
- metrics: `true`
- ServiceMonitor: `true`
- DB bootstrap: `true`
- `cmict-share.yaml` import: `true`
- target registry repo: `sealos.hub:5000/kube4`
- wait timeout: `10m`

这是一套 “单点 Nacos + 外部 MySQL + 默认开启监控 + 默认导入业务基线配置” 的交付方案。

## 默认拓扑

默认安装会创建：

- 1 个 `Deployment/nacos`
- 1 个 `Service/nacos`
- 1 个 `ConfigMap/nacos`
- 1 个 `ConfigMap/nacos-config`
- 1 个 `ConfigMap/nacos-bootstrap-assets`
- 1 个 `Secret/nacos-bootstrap-db-auth`
- 1 个 `Job/nacos-db-bootstrap`
- 1 个 `ServiceMonitor/nacos`，前提是集群支持 `ServiceMonitor` CRD

默认不会创建：

- MySQL
- Redis
- 独立 exporter sidecar
- 多副本 Nacos 集群

也就是说，`apps_nacos` 默认依赖已经存在的 MySQL，而不负责数据库本体交付。

## 默认访问地址、端口和账户

### 集群内访问

默认 Service 名称为 `nacos`，因此常用地址是：

- `http://nacos.aict.svc.cluster.local:8848/nacos`
- `nacos.aict.svc.cluster.local:8848`

### 集群外访问

默认暴露 NodePort：

- Nacos HTTP: `http://<NODE_IP>:30094/nacos`
- Nacos gRPC: `<NODE_IP>:30930`

### 数据库依赖

Nacos 默认连接这组数据库参数：

- host: `mysql-0.mysql.aict`
- port: `3306`
- database: `frame_nacos_demo`
- user: `root`
- password: 安装时通过 `--mysql-password` 显式传入

建议生产环境始终显式传入数据库密码，不要依赖任何外部“默认密码假设”。

### Nacos 管理账户

清洗后的标准 SQL 会创建：

- 用户：`nacos`
- 角色：`ROLE_ADMIN`

仓库里只保存了 bcrypt hash，不保存明文管理员密码。因此安装完成后，建议立即验证登录并在你的环境里重置成可控密码。

## 基线资产与版本收敛策略

这个仓库里和 Nacos 基线有关的文件主要有 4 个：

- `frame_nacos_demo.sql`
- `cmict-share.yaml`
- `tools/normalize_nacos_sql.py`
- `import-nacos.sh`

当前策略是：

- `frame_nacos_demo.sql` 只保留当前最新版、清洗后的标准建表与基线数据
- 不再保留一堆历史重复 SQL 版本
- 不再把历史业务配置固化在 SQL 里
- `cmict-share.yaml` 作为最新版共享配置，在安装时单独导入

这样做的好处是：

- SQL 更容易维护
- 业务配置和表结构职责分离
- 以后更新 `cmict-share.yaml` 时不需要重新整理整份 SQL dump

## 和其他组件的依赖关系

### Nacos 依赖谁

默认依赖：

- MySQL

默认不依赖：

- Redis
- MinIO
- RabbitMQ
- MongoDB
- Milvus

### 谁常常会依赖 Nacos

在你的整体系统里，Nacos 更常见的角色是“被业务系统消费”：

- Java / Spring Cloud 服务
- 网关
- 管理后台
- 业务 API 服务

### 和 MySQL 的契约

如果你使用我们当前的 `apps_mysql` 默认安装方案，Nacos 默认数据库地址就是：

- `mysql-0.mysql.aict:3306`

这也是为什么安装器默认值直接写成了 `--mysql-host mysql-0.mysql.aict`。

### 和 Redis、RabbitMQ、其他业务组件的关系

`cmict-share.yaml` 里可能包含这些系统的默认访问地址或示例凭据，用来快速初始化业务基线配置。

这意味着：

- Nacos 本体启动不依赖它们
- 但导入的业务配置可能引用它们
- 如果你不是在完整演示环境里部署，应该在导入前审阅 `cmict-share.yaml`

## 默认资源需求

Nacos 主容器当前显式声明：

- CPU request: `100m`
- Memory request: `128Mi`
- CPU limit: `2`
- Memory limit: `4Gi`

当前默认是单副本，因此默认持续资源需求就是：

| 项目 | 默认值 |
| --- | --- |
| CPU request | `100m` |
| Memory request | `128Mi` |
| CPU limit | `2` |
| Memory limit | `4Gi` |

### 启动期额外资源

安装阶段还会临时拉起一个 `nacos-db-bootstrap` Job 去初始化数据库。它不是常驻负载，但你需要为它预留少量瞬时调度空间。

## 存储需求

当前默认 Nacos 是单点 Deployment，不额外声明 PVC，所以默认存储需求主要来自：

- 外部 MySQL 的存储
- Nacos 所依赖的日志与容器层临时存储

也就是说，`apps_nacos` 默认不负责持久化数据库内容，真正的数据持久化压力在 MySQL 那边。

## 监控设计

监控默认就是开启的：

- `--enable-metrics`
- `--enable-servicemonitor`

默认行为：

- metrics 通过 Nacos Prometheus endpoint 暴露
- `ServiceMonitor` 默认创建
- 默认标签为 `monitoring.archinfra.io/stack=default`

Prometheus 默认抓取路径是：

- `/nacos/actuator/prometheus`

如果集群里没有 `ServiceMonitor` CRD，安装器会自动降级：

- 保留 metrics
- 跳过 `ServiceMonitor`

不会因为监控 CRD 缺失导致整套 Nacos 安装失败。

## 快速开始

### 1. 看帮助

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

### 3. 查看状态

```bash
./nacos-installer-amd64.run status -n aict
```

### 4. 卸载

```bash
./nacos-installer-amd64.run uninstall -n aict -y
```

## 常见使用场景

### 场景 1：直接对接默认 MySQL

```bash
./nacos-installer-amd64.run install \
  --mysql-password 'passw0rd' \
  -y
```

### 场景 2：MySQL 不在默认地址

```bash
./nacos-installer-amd64.run install \
  --mysql-host mysql.example.svc \
  --mysql-port 3306 \
  --mysql-database frame_nacos_demo \
  --mysql-user root \
  --mysql-password 'StrongPassword' \
  -y
```

### 场景 3：只部署 Nacos，不做数据库初始化

```bash
./nacos-installer-amd64.run install \
  --mysql-password 'StrongPassword' \
  --disable-db-bootstrap \
  --disable-cmict-share-import \
  -y
```

### 场景 4：保留建库建表，但不导入 `cmict-share.yaml`

```bash
./nacos-installer-amd64.run install \
  --mysql-password 'StrongPassword' \
  --disable-cmict-share-import \
  -y
```

### 场景 5：修改 HTTP NodePort

```bash
./nacos-installer-amd64.run install \
  --mysql-password 'StrongPassword' \
  --node-port 30094 \
  -y
```

### 场景 6：目标仓库已经有镜像

```bash
./nacos-installer-amd64.run install \
  --mysql-password 'StrongPassword' \
  --skip-image-prepare \
  -y
```

## 自定义参数怎么处理

普通场景优先用安装器显式暴露的参数，例如：

- `--mysql-host`
- `--mysql-port`
- `--mysql-database`
- `--mysql-user`
- `--mysql-password`
- `--node-port`
- `--enable-metrics`
- `--enable-servicemonitor`
- `--enable-db-bootstrap`
- `--enable-cmict-share-import`
- `--registry`
- `--skip-image-prepare`

如果你要做更深的 Nacos JVM、环境变量、Probe、Service 级定制，当前仓库更推荐直接改 manifest 再重新打包，而不是在安装器上继续堆非常多的一次性参数。

也就是说，这个仓库的设计取向是：

- 常见运维参数暴露给安装器
- 复杂结构型变更留给 manifest / 仓库级维护

## 给新维护者和 AI 的执行规约

如果你把安装包和 README 交给一个没有背景信息的人或 AI，建议把下面这些规则视为默认执行策略：

### 默认优先策略

没有特殊要求时，优先使用：

- namespace: `aict`
- MySQL host: `mysql-0.mysql.aict`
- MySQL database: `frame_nacos_demo`
- 显式传入 `--mysql-password`
- 保持 metrics 开启
- 保持 `ServiceMonitor` 开启
- 保持 DB bootstrap 开启

### 成功标准

可以把这些看作安装成功信号：

- `Deployment/nacos` 为 `Available`
- `Service/nacos` 存在
- `Job/nacos-db-bootstrap` 成功完成
- `kubectl logs` 中没有数据库初始化失败信息
- 如果集群支持 `ServiceMonitor`，则 `ServiceMonitor/nacos` 存在

### 失败信号

- `nacos-db-bootstrap` Job `Failed`
- Nacos Pod `CrashLoopBackOff`
- Nacos 启动成功但无法连 MySQL
- `cmict-share.yaml` 导入时报 SQL 或编码错误

### 操作建议

- 先确认 MySQL 连通
- 再执行安装
- 安装后先验证 `Job` 成功，再验证 `Deployment`
- 对生产环境，先审阅 `cmict-share.yaml` 再导入

## 常见排障命令

```bash
./nacos-installer-amd64.run status -n aict
kubectl get pods,svc,deploy,job,configmap,secret -n aict
kubectl logs -n aict deploy/nacos
kubectl logs -n aict job/nacos-db-bootstrap --all-containers=true
kubectl get servicemonitor -A | grep nacos
```

## 仓库结构

- `build.sh`
  多架构离线包构建入口
- `install.sh`
  自解包安装器模板
- `images/image.json`
  多架构镜像清单
- `manifests/nacos.yaml`
  Nacos manifest 模板
- `frame_nacos_demo.sql`
  清洗后的最新版标准 SQL
- `cmict-share.yaml`
  最新版共享业务配置
- `import-nacos.sh`
  手工重跑基线导入的脚本
- `tools/normalize_nacos_sql.py`
  SQL 清洗辅助脚本

## GitHub Actions 与发布

推送到 `main` / `master`：

- 构建 `amd64` / `arm64` 离线包
- 上传构建产物

推送 `v*` tag：

- 构建双架构安装包
- 发布 GitHub Release
- 上传 `.run` 和 `.sha256`

## 说明

- 运行时不依赖 `jq`
- `.run` payload 提取逻辑已经做过稳健化处理
- 如果 Prometheus Operator CRD 不存在，安装器会自动跳过 `ServiceMonitor`
